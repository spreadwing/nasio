from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from nasio.core.security import get_current_user, require_admin
from nasio.services.auth_service import auth_service, AuthUser, UserRole

router = APIRouter(prefix="/auth", tags=["Authentication & Users"])


class LoginRequest(BaseModel):
    username: str = Field(..., description="用户名")
    password: str = Field(..., description="密码")


class CreateUserRequest(BaseModel):
    username: str = Field(..., description="用户名")
    password: str = Field(..., description="初始密码 (至少6位)")
    role: str = Field(default=UserRole.USER, description="用户角色 (ADMIN 或 USER)")


class UpdateUserRequest(BaseModel):
    password: Optional[str] = Field(None, description="新密码 (若留空则不修改)")
    role: Optional[str] = Field(None, description="新角色 (ADMIN 或 USER)")


# -------------------------------------------------------------
# 1. 登录与身份校验端点
# -------------------------------------------------------------
@router.post("/login")
async def login(payload: LoginRequest) -> Dict[str, Any]:
    """通过用户名与密码验证登录，返回访问 Token 及用户信息"""
    user_auth = auth_service.authenticate_basic(payload.username, payload.password)
    if not user_auth:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码错误",
        )

    # 如果是 master 用户
    if user_auth.is_master:
        master_token = auth_service.get_master_token()
        return {
            "token": master_token,
            "user": {
                "id": "master",
                "username": user_auth.username,
                "role": user_auth.role,
                "is_master": True,
                "is_admin": True,
            },
        }

    # 具体普通或管理员用户
    user_obj = auth_service.get_user_by_id(user_auth.id)
    return {
        "token": user_obj.token if user_obj else "",
        "user": {
            "id": user_auth.id,
            "username": user_auth.username,
            "role": user_auth.role,
            "is_master": False,
            "is_admin": user_auth.is_admin,
        },
    }


@router.get("/me")
async def get_me(user: AuthUser = Depends(get_current_user)) -> Dict[str, Any]:
    """获取当前登录会话的用户身份与权限上下文"""
    return {
        "id": user.id,
        "username": user.username,
        "role": user.role,
        "is_master": user.is_master,
        "is_admin": user.is_admin,
    }


# -------------------------------------------------------------
# 2. Master 安全 Token 管理 (仅管理员权限)
# -------------------------------------------------------------
@router.get("/token", dependencies=[Depends(require_admin)])
async def get_token() -> Dict[str, Any]:
    """获取当前生效的 Master Token"""
    token = auth_service.get_master_token()
    return {"master_token": token}


@router.post("/token/regenerate", dependencies=[Depends(require_admin)])
async def regenerate_token() -> Dict[str, Any]:
    """重新生成 Master Token 并持久化保存到 auth.json"""
    new_token = auth_service.regenerate_master_token()
    return {
        "success": True,
        "message": "Master Token 重新生成成功",
        "master_token": new_token,
    }


# -------------------------------------------------------------
# 3. 用户账号与权限管理 (仅管理员权限)
# -------------------------------------------------------------
@router.get("/users", dependencies=[Depends(require_admin)])
async def list_users() -> Dict[str, Any]:
    """列出系统所有已配置的用户"""
    users = auth_service.list_users()
    return {"users": users, "total": len(users)}


@router.post("/users", dependencies=[Depends(require_admin)])
async def create_user(payload: CreateUserRequest) -> Dict[str, Any]:
    """创建新用户并分配权限 (ADMIN 或 USER)"""
    try:
        user = auth_service.create_user(
            username=payload.username,
            password=payload.password,
            role=payload.role,
        )
        return {"success": True, "user": user.to_safe_dict()}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.put("/users/{user_id}", dependencies=[Depends(require_admin)])
async def update_user(user_id: str, payload: UpdateUserRequest) -> Dict[str, Any]:
    """更新指定用户的密码或角色权限"""
    try:
        user = auth_service.update_user(
            user_id=user_id,
            password=payload.password,
            role=payload.role,
        )
        return {"success": True, "user": user.to_safe_dict()}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.delete("/users/{user_id}", dependencies=[Depends(require_admin)])
async def delete_user(user_id: str, current_user: AuthUser = Depends(require_admin)) -> Dict[str, Any]:
    """删除指定用户"""
    if current_user.id == user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="不能删除当前登录的自身账号")
    success = auth_service.delete_user(user_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="用户不存在")
    return {"success": True, "user_id": user_id}


@router.post("/users/{user_id}/token/regenerate", dependencies=[Depends(require_admin)])
async def regenerate_user_token(user_id: str) -> Dict[str, Any]:
    """为指定用户重新生成专属访问 Token 并持久化保存 (仅管理员权限)"""
    try:
        new_token = auth_service.regenerate_user_token(user_id)
        user = auth_service.get_user_by_id(user_id)
        return {
            "success": True,
            "message": "用户 Token 重新生成成功",
            "token": new_token,
            "user": user.to_safe_dict() if user else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
