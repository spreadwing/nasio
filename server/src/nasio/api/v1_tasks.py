import logging
import asyncio
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query, status
from nasio.core.security import verify_auth_token, get_configured_token
from nasio.services.auth_service import auth_service, AuthUser, UserRole

from nasio.services.task_engine import task_engine, TaskModel

logger = logging.getLogger("nasio.api.tasks")
router = APIRouter(prefix="/tasks", tags=["Tasks"])


class CreateTaskRequest(BaseModel):
    url: str
    save_dir: str = "/volume1/Download"
    filename: Optional[str] = None
    engine_override: str = "auto"
    extract_audio_only: bool = False
    agent_task_id: Optional[str] = None


@router.post("", dependencies=[Depends(verify_auth_token)])
async def create_task(req: CreateTaskRequest) -> Dict[str, Any]:
    """创建异步下载任务"""
    import os
    from nasio.services.downloader_service import DownloaderService
    from nasio.services.agent_task_service import agent_task_service

    agent_task_id = req.agent_task_id
    if not agent_task_id:
        target_name = req.filename or os.path.basename(req.url.split("?")[0]) or req.url[:30]
        task = agent_task_service.start_task(
            title=f"离线下载: {target_name}",
            description=f"[自动托管] URL: {req.url}",
            total_steps=1,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(
            agent_task_id,
            step_name="派发下载任务",
            status="RUNNING",
            progress=10.0,
        )

    return DownloaderService.dispatch_download(
        url=req.url,
        save_dir=req.save_dir,
        filename=req.filename,
        engine_override=req.engine_override,
        extract_audio_only=req.extract_audio_only,
        agent_task_id=agent_task_id,
    )


@router.get("", dependencies=[Depends(verify_auth_token)], response_model=List[TaskModel])
async def list_tasks(limit: int = 100) -> List[TaskModel]:
    """获取所有后台异步任务列表（包含本地引擎与外部下载器任务）"""
    return task_engine.list_tasks(limit=limit)


class BatchTasksRequest(BaseModel):
    task_ids: List[str]


class BatchDeleteRequest(BaseModel):
    task_ids: List[str]
    delete_files: bool = False


@router.post("/clear-failed", dependencies=[Depends(verify_auth_token)])
async def clear_failed_tasks(delete_files: bool = Query(False)) -> Dict[str, Any]:
    """一键清空所有失败任务（包含本地引擎与外部下载器）"""
    cleared = task_engine.clear_failed_tasks(delete_files=delete_files)
    return {"success": True, "cleared_count": cleared, "delete_files": delete_files}


@router.post("/batch-pause", dependencies=[Depends(verify_auth_token)])
async def batch_pause_tasks(req: BatchTasksRequest) -> Dict[str, Any]:
    """批量暂停下载任务"""
    from nasio.services.downloader_service import DownloaderService
    results = {}
    for tid in req.task_ids:
        if tid.startswith("qb_"):
            existing = task_engine.get_task(tid)
            is_seeding = False
            if existing and existing.detail:
                st = str(existing.detail.get("state", "")).lower()
                is_seeding = st in ["uploading", "stalledup", "forcedup", "forceup", "queuedup", "checkingup"] or existing.status.value == "COMPLETED"

            ok = DownloaderService.pause_torrent(tid[3:])
            results[tid] = ok
            if ok:
                new_state = "stoppedUP" if is_seeding else "stoppedDL"
                new_status = "COMPLETED" if is_seeding else "PAUSED"
                asyncio.create_task(task_engine._broadcast({
                    "event": "TASK_UPDATE",
                    "data": {"task_id": tid, "status": new_status, "detail": {"state": new_state, "speed": "0 B/s"}}
                }))
        else:
            results[tid] = False
    return {"success": True, "results": results}


@router.post("/batch-resume", dependencies=[Depends(verify_auth_token)])
async def batch_resume_tasks(req: BatchTasksRequest) -> Dict[str, Any]:
    """批量恢复下载任务"""
    from nasio.services.downloader_service import DownloaderService
    results = {}
    for tid in req.task_ids:
        if tid.startswith("qb_"):
            existing = task_engine.get_task(tid)
            is_seeding_stopped = False
            if existing and existing.detail:
                st = str(existing.detail.get("state", "")).lower()
                is_seeding_stopped = st in ["pausedup", "stoppedup", "completed"] or existing.status.value == "COMPLETED"

            ok = DownloaderService.resume_torrent(tid[3:])
            results[tid] = ok
            if ok:
                new_state = "uploading" if is_seeding_stopped else "downloading"
                new_status = "COMPLETED" if is_seeding_stopped else "RUNNING"
                asyncio.create_task(task_engine._broadcast({
                    "event": "TASK_UPDATE",
                    "data": {"task_id": tid, "status": new_status, "detail": {"state": new_state}}
                }))
        else:
            results[tid] = False
    return {"success": True, "results": results}


@router.post("/batch-delete", dependencies=[Depends(verify_auth_token)])
async def batch_delete_tasks(req: BatchDeleteRequest) -> Dict[str, Any]:
    """批量删除下载任务"""
    results = {}
    for tid in req.task_ids:
        ok = task_engine.cancel_task(tid, delete_files=req.delete_files)
        results[tid] = ok
    return {"success": True, "results": results}


@router.get("/{task_id}", dependencies=[Depends(verify_auth_token)])
async def get_task(task_id: str) -> Dict[str, Any]:
    """获取指定任务状态"""
    t = task_engine.get_task(task_id)
    if not t:
        return {"error": f"Task '{task_id}' not found"}
    return t.model_dump()


@router.post("/{task_id}/cancel", dependencies=[Depends(verify_auth_token)])
async def cancel_task(task_id: str, delete_files: bool = Query(False)) -> Dict[str, Any]:
    """取消或删除运行中的任务"""
    success = task_engine.cancel_task(task_id, delete_files=delete_files)
    return {"task_id": task_id, "cancelled": success, "delete_files": delete_files}


@router.delete("/{task_id}", dependencies=[Depends(verify_auth_token)])
async def delete_task(task_id: str, delete_files: bool = Query(False)) -> Dict[str, Any]:
    """删除任务记录，支持同时清理本地下载文件"""
    success = task_engine.cancel_task(task_id, delete_files=delete_files)
    return {"task_id": task_id, "deleted": success, "delete_files": delete_files}


@router.post("/{task_id}/pause", dependencies=[Depends(verify_auth_token)])
async def pause_task(task_id: str) -> Dict[str, Any]:
    """暂停下载任务"""
    if task_id.startswith("qb_"):
        from nasio.services.downloader_service import DownloaderService
        existing = task_engine.get_task(task_id)
        is_seeding = False
        if existing and existing.detail:
            st = str(existing.detail.get("state", "")).lower()
            is_seeding = st in ["uploading", "stalledup", "forcedup", "forceup", "queuedup", "checkingup"] or existing.status.value == "COMPLETED"

        success = DownloaderService.pause_torrent(task_id[3:])
        if success:
            new_state = "stoppedUP" if is_seeding else "stoppedDL"
            new_status = "COMPLETED" if is_seeding else "PAUSED"
            asyncio.create_task(task_engine._broadcast({
                "event": "TASK_UPDATE",
                "data": {"task_id": task_id, "status": new_status, "detail": {"state": new_state, "speed": "0 B/s"}}
            }))
        return {"task_id": task_id, "paused": success}
    return {"task_id": task_id, "paused": False, "error": "Pause not supported for local task"}


@router.post("/{task_id}/resume", dependencies=[Depends(verify_auth_token)])
async def resume_task(task_id: str) -> Dict[str, Any]:
    """恢复/继续下载任务"""
    if task_id.startswith("qb_"):
        from nasio.services.downloader_service import DownloaderService
        existing = task_engine.get_task(task_id)
        is_seeding_stopped = False
        if existing and existing.detail:
            st = str(existing.detail.get("state", "")).lower()
            is_seeding_stopped = st in ["pausedup", "stoppedup", "completed"] or existing.status.value == "COMPLETED"

        success = DownloaderService.resume_torrent(task_id[3:])
        if success:
            new_state = "uploading" if is_seeding_stopped else "downloading"
            new_status = "COMPLETED" if is_seeding_stopped else "RUNNING"
            asyncio.create_task(task_engine._broadcast({
                "event": "TASK_UPDATE",
                "data": {"task_id": task_id, "status": new_status, "detail": {"state": new_state}}
            }))
        return {"task_id": task_id, "resumed": success}
    return {"task_id": task_id, "resumed": False, "error": "Resume not supported for local task"}


@router.post("/{task_id}/recheck", dependencies=[Depends(verify_auth_token)])
async def recheck_task(task_id: str) -> Dict[str, Any]:
    """强制重新校验种子文件"""
    if task_id.startswith("qb_"):
        from nasio.services.downloader_service import DownloaderService
        success = DownloaderService.recheck_torrent(task_id[3:])
        return {"task_id": task_id, "rechecked": success}
    return {"task_id": task_id, "rechecked": False, "error": "Recheck only supported for qBittorrent tasks"}



@router.websocket("/ws")
async def websocket_tasks_endpoint(websocket: WebSocket, token: Optional[str] = Query(None)):
    """
    WebSocket 实时状态与下载速率广播通道
    供 Flutter 客户端建立连接监听任务动态 (需凭据鉴权)
    """
    query_token = (token or websocket.query_params.get("token", "")).strip()
    auth_header = websocket.headers.get("Authorization", "").strip()
    effective_token = ""
    if query_token:
        effective_token = query_token
    elif auth_header.startswith("Bearer "):
        effective_token = auth_header[7:].strip()

    user = None
    if effective_token:
        user = auth_service.authenticate_token(effective_token)

    # 如果未配置 Master Token 且系统中没有任何用户，回退至内网免密信任模式
    configured = get_configured_token()
    users = auth_service.list_users()
    if not user and not configured and len(users) == 0:
        user = AuthUser(
            id="master",
            username="Master",
            role=UserRole.ADMIN,
            is_master=True,
        )

    if not user:
        logger.warning(
            "拒绝未授权的 WebSocket 连接尝试 (token: %s)",
            effective_token[:8] + "..." if effective_token else "None"
        )
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="未授权访问: 凭据无效或缺失")
        return

    await websocket.accept()
    task_engine.register_ws(websocket)
    logger.info("Flutter WebSocket client connected: %s", user.username)
    try:
        while True:
            # 保持长连接并接收客户端心跳
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        logger.info("Flutter WebSocket client disconnected: %s", user.username)
    finally:
        task_engine.unregister_ws(websocket)
