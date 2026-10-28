import os
import base64
from typing import List, Optional
from fastapi import HTTPException, Security, Request, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from nasio.core.config import get_app_config
from nasio.services.auth_service import auth_service, AuthUser, UserRole

security_bearer = HTTPBearer(auto_error=False)


def get_configured_token() -> str:
    """获取当前生效的 Master Token (优先 auth.json，回退环境变量)"""
    return auth_service.get_master_token()


def parse_request_auth(request: Request) -> Optional[AuthUser]:
    """从请求头或 Query 参数解析认证上下文"""
    auth_header = request.headers.get("Authorization", "").strip()
    query_token = request.query_params.get("token", "").strip()

    # 1. Bearer Token 或 Query Token
    token = ""
    if auth_header.startswith("Bearer "):
        token = auth_header[7:].strip()
    elif query_token:
        token = query_token

    if token:
        user = auth_service.authenticate_token(token)
        if user:
            return user

    # 2. HTTP Basic Auth
    if auth_header.startswith("Basic "):
        try:
            b64_str = auth_header[6:].strip()
            decoded = base64.b64decode(b64_str).decode("utf-8")
            if ":" in decoded:
                username, password = decoded.split(":", 1)
                user = auth_service.authenticate_basic(username, password)
                if user:
                    return user
        except Exception:
            pass

    # 3. 如果未配置 Master Token 且系统中没有任何用户，回退至内网免密信任模式 (超级管理员)
    configured = get_configured_token()
    users = auth_service.list_users()
    if not configured and len(users) == 0:
        return AuthUser(
            id="master",
            username="Master",
            role=UserRole.ADMIN,
            is_master=True,
        )

    return None


async def get_current_user(request: Request) -> AuthUser:
    """
    依赖注入: 获取当前登录用户
    若未认证或凭证无效，抛出 401
    """
    # 优先读取中间件已解析并注入的身份
    if hasattr(request.state, "auth_user") and request.state.auth_user:
        return request.state.auth_user

    user = parse_request_auth(request)
    if user:
        request.state.auth_user = user
        return user

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="未授权访问: 缺少或无效的凭证 (支持 Bearer Token 或 HTTP Basic 认证)",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def require_admin(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    """
    依赖注入: 强校验管理员权限 (ADMIN / Master)
    若角色为普通用户，拦截并返回 403 Forbidden
    """
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足: 该操作仅限系统管理员执行",
        )
    return user


async def verify_auth_token(user: AuthUser = Depends(get_current_user)) -> bool:
    """
    兼容历史接口依赖: 只要是合法用户或 Master 即可放行
    """
    return True


def validate_sandbox_path(target_path: str, allowed_paths: Optional[List[str]] = None) -> str:
    """
    路径沙箱规整化与安全校验
    1. 解析符号链接与相对路径 (os.path.realpath)
    2. 校验解析后的真实路径必须以白名单中某个路径为前缀
    """
    if allowed_paths is None:
        cfg = get_app_config()
        allowed_paths = cfg.storage.allowed_paths

    # 转为标准绝对路径
    real_path = os.path.realpath(os.path.expanduser(target_path))

    # 在 Windows 测试环境下允许通用路径格式适配
    for allowed in allowed_paths:
        real_allowed = os.path.realpath(os.path.expanduser(allowed))
        # 兼容跨平台大小写比较
        if os.name == "nt":
            if real_path.lower() == real_allowed.lower() or real_path.lower().startswith(real_allowed.lower() + os.sep):
                return real_path
        else:
            if real_path == real_allowed or real_path.startswith(real_allowed + os.sep):
                return real_path

    raise PermissionError(
        f"Security Sandbox Violation: Path '{target_path}' (resolved: '{real_path}') is outside allowed whitelist: {allowed_paths}"
    )


def get_target_nas_owner(reference_path: Optional[str] = None) -> tuple[int, int]:
    """
    获取目标路径应对齐的宿主机 UID 与 GID
    """
    default_uid = int(os.environ.get("NAS_UID") or os.environ.get("PUID") or 1000)
    default_gid = int(os.environ.get("NAS_GID") or os.environ.get("PGID") or 1000)

    if reference_path:
        curr = os.path.abspath(reference_path)
        while curr and curr != os.path.dirname(curr):
            if os.path.exists(curr):
                try:
                    st = os.stat(curr)
                    uid = getattr(st, "st_uid", 0)
                    gid = getattr(st, "st_gid", 0)
                    if uid != 0 or gid != 0:
                        return (uid if uid != 0 else default_uid, gid if gid != 0 else default_gid)
                except OSError:
                    pass
                break
            curr = os.path.dirname(curr)

    return (default_uid, default_gid)


def apply_nas_permissions(path: str, reference_path: Optional[str] = None) -> None:
    """
    对新建或移动后的目录/文件对齐宿主机属主 (chown) 并放开读写权限 (目录 0777 / 文件 0666)
    """
    if not os.path.exists(path):
        return
    uid, gid = get_target_nas_owner(reference_path or os.path.dirname(path))
    try:
        if os.path.isdir(path):
            os.chmod(path, 0o777)
        else:
            os.chmod(path, 0o666)
    except OSError:
        pass
    if hasattr(os, "chown"):
        try:
            os.chown(path, uid, gid)
        except OSError:
            pass


def ensure_nas_compatible_dir(target_dir: str, reference_path: Optional[str] = None) -> str:
    """
    递归创建目录，并对所有新创建的层级自动设置 0777 权限及继承宿主机非 root 属主 (UID:GID)
    """
    abs_target = os.path.abspath(target_dir)
    uid, gid = get_target_nas_owner(reference_path or abs_target)

    missing_dirs = []
    curr = abs_target
    while curr and not os.path.exists(curr):
        missing_dirs.append(curr)
        parent = os.path.dirname(curr)
        if parent == curr:
            break
        curr = parent

    os.makedirs(abs_target, mode=0o777, exist_ok=True)

    dirs_to_fix = missing_dirs if missing_dirs else [abs_target]
    for d in reversed(dirs_to_fix):
        try:
            os.chmod(d, 0o777)
        except OSError:
            pass
        if hasattr(os, "chown"):
            try:
                os.chown(d, uid, gid)
            except OSError:
                pass

    return abs_target
