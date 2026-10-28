import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from nasio.core.config import get_app_config
from nasio.core.security import get_configured_token, parse_request_auth
from nasio.services.auth_service import auth_service, AuthUser, UserRole
from nasio.mcp.server import mcp
from nasio.api.v1_auth import router as auth_router
from nasio.api.v1_config import router as config_router
from nasio.api.v1_trash import router as trash_router
from nasio.api.v1_tasks import router as tasks_router
from nasio.api.v1_downloaders import router as downloaders_router
from nasio.api.v1_agent_tasks import router as agent_tasks_router
from nasio.api.v1_missing_mcp import router as missing_mcp_router
from nasio.api.v1_skills import router as skills_router
from nasio.api.v1_rss import router as rss_router
from nasio.api.v1_chat import router as chat_router
from nasio.services.rss_service import rss_service

# 配置全局 umask 为 0000，确保新建目录(0777)与文件(0666)对 SMB/绿联文件管理器完全开放，消除权限冲突
try:
    os.umask(0o000)
except Exception:
    pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
logger = logging.getLogger("nasio.main")


# 初始化 FastMCP Streamable HTTP 与经典 SSE 协议栈
try:
    sse_app = mcp.sse_app()
    _ = mcp.streamable_http_app()
    streamable_asgi = StreamableHTTPASGIApp(mcp.session_manager)
except Exception as e:
    logger.warning("MCP 传输层应用初始化异常: %s. MCP 工具将仅通过运行时暴露。", e)
    sse_app = None
    streamable_asgi = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动时日志
    cfg = get_app_config()
    logger.info("==================================================")
    logger.info("🚀 Nasio (绿联 NAS 智能中枢与资产管家) 启动中...")
    logger.info("📦 允许沙箱白名单: %s", cfg.storage.allowed_paths)
    logger.info("🗑️ 回收站挂载路径: %s", cfg.trash.trash_dir)
    token = get_configured_token()
    if token:
        logger.info("🔒 Bearer Token 鉴权已激活 (Token 已配置)")
    else:
        logger.warning("⚠️ 未配置 MCP_AUTH_TOKEN 环境变量，运行在内网免密信任模式！")
    logger.info("🌐 统一网关监听端口: :8000 (同时承载 MCP /sse, /mcp 与 REST /api/v1)")
    logger.info("==================================================")

    # 启动 RSS 订阅后台定时轮询任务调度器
    rss_service.start_scheduler()

    # 启动 FastMCP Streamable HTTP 会话管理器协程池
    if hasattr(mcp, "session_manager") and mcp.session_manager:
        async with mcp.session_manager.run():
            yield
    else:
        yield

    # 优雅关闭 RSS 轮询任务
    rss_service.stop_scheduler()
    logger.info("🛑 Nasio 正在优雅退出...")


app = FastAPI(
    title="Nasio",
    description="绿联 NAS 智能中枢与资产管家: 统一 MCP 智能体协议与 Flutter 跨端管理控制台",
    version="1.0.0",
    lifespan=lifespan,
)

# 允许跨域请求 (供前端/Flutter Web/局域网客户端访问)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# 全局认证与 Host 头规范化中间件 (双模支持 Bearer Token 与 HTTP Basic 账号密码)
@app.middleware("http")
async def global_auth_middleware(request: Request, call_next):
    # 规整化 Host 头为 localhost:8000，避免 FastMCP SSE 拦截局域网 IP 与外部域名
    new_headers = []
    for k, v in request.scope.get("headers", []):
        if k.lower() == b"host":
            new_headers.append((b"host", b"localhost:8000"))
        else:
            new_headers.append((k, v))
    request.scope["headers"] = new_headers

    # 静态文档、健康检查端点、登录端点及 CORS 预检请求 (OPTIONS) 免鉴权
    if request.method == "OPTIONS" or request.url.path in [
        "/",
        "/docs",
        "/openapi.json",
        "/health",
        "/api/v1/auth/login",
    ]:
        return await call_next(request)

    # 尝试解析当前请求凭据 (Bearer Token 或 Basic Auth)
    user = parse_request_auth(request)
    if user:
        # 将鉴权身份注入请求上下文状态
        request.state.auth_user = user
        return await call_next(request)

    # 若未匹配且系统配置了 Token 或已存在用户，返回 401
    configured_token = get_configured_token()
    users_list = auth_service.list_users()
    if configured_token or len(users_list) > 0:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"error": "未授权访问: 凭据无效或缺失 (请提供正确的 Bearer Token 或 HTTP Basic 账号密码)"},
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 内网免密信任模式：自动赋予超级管理员身份
    request.state.auth_user = AuthUser(
        id="master",
        username="Master",
        role=UserRole.ADMIN,
        is_master=True,
    )
    return await call_next(request)


# 健康检查端点
@app.get("/health", tags=["System"])
async def health_check():
    return {"status": "ok", "app": "Nasio", "version": "1.0.0"}


# 注册 RESTful API 路由 (供 Flutter 跨平台客户端调用)
app.include_router(auth_router, prefix="/api/v1")
app.include_router(config_router, prefix="/api/v1")
app.include_router(trash_router, prefix="/api/v1")
app.include_router(tasks_router, prefix="/api/v1")
app.include_router(downloaders_router, prefix="/api/v1")
app.include_router(agent_tasks_router, prefix="/api/v1")
app.include_router(missing_mcp_router, prefix="/api/v1")
app.include_router(skills_router, prefix="/api/v1")
app.include_router(rss_router, prefix="/api/v1")
app.include_router(chat_router, prefix="/api/v1")

# -------------------------------------------------------------
# MCP 协议路由：双模支持 (Streamable HTTP + 经典 SSE)
# -------------------------------------------------------------
if streamable_asgi:
    # 1. /mcp 标准端点：服务现代 Streamable HTTP 客户端 (Antigravity 等)
    @app.api_route("/mcp", methods=["GET", "POST", "DELETE"], tags=["MCP"])
    async def handle_mcp_streamable(request: Request):
        return await streamable_asgi(request.scope, request.receive, request._send)

    # 2. /sse POST 端点：解决 Antigravity 等客户端以 serverUrl 发送 POST 报 405 的问题
    @app.post("/sse", tags=["MCP"])
    async def handle_sse_post(request: Request):
        return await streamable_asgi(request.scope, request.receive, request._send)

if sse_app:
    # 3. 规整 /messages 无斜杠 POST，避免 307 重定向
    @app.post("/messages", tags=["MCP"])
    async def handle_messages_no_slash(request: Request):
        return await sse_app(request.scope, request.receive, request._send)

    # 4. 挂载经典 SSE 子应用 (暴露 GET /sse 与 POST /messages/)
    app.mount("/", sse_app)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("nasio.main:app", host="0.0.0.0", port=8000, reload=False)
