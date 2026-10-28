from typing import Optional, Dict, Any
from fastapi import APIRouter, Depends, Query
from nasio.core.security import verify_auth_token, require_admin
from nasio.services.trash_service import TrashService

router = APIRouter(prefix="/trash", tags=["Recycle Bin"])


@router.get("", dependencies=[Depends(verify_auth_token)])
async def list_trash(
    keyword: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
) -> Dict[str, Any]:
    """分页与关键字查询回收站文件"""
    return TrashService.list_trash(keyword=keyword, page=page, limit=limit)


@router.post("/{file_id}/restore", dependencies=[Depends(verify_auth_token)])
async def restore_trash_file(file_id: str, payload: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """一键恢复回收站文件至原路"""
    import time
    from nasio.services.agent_task_service import agent_task_service

    custom_dir = payload.get("custom_target_dir") if payload else None
    agent_task_id = payload.get("agent_task_id") if payload else None
    is_auto = False
    if not agent_task_id:
        is_auto = True
        task = agent_task_service.start_task(
            title=f"回收站还原: {file_id}",
            description=f"[自动托管] 目标: {custom_dir or '原路径'}",
            total_steps=1,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行文件还原", status="RUNNING", progress=50.0)

    res = TrashService.restore_file(file_id, custom_dir)
    agent_task_service.add_sub_action(
        agent_task_id=agent_task_id,
        action_type="TRASH_RESTORE",
        action_id=f"rst_{int(time.time())}",
        summary=f"还原回收站文件: {file_id}",
        status="COMPLETED",
    )
    if is_auto:
        agent_task_service.report_step(agent_task_id, step_name="文件还原完成", status="COMPLETED", progress=100.0)
        agent_task_service.complete_task(agent_task_id, result=res)
    return res


@router.delete("/{file_id}", dependencies=[Depends(require_admin)])
async def permanently_delete_trash_file(file_id: str) -> Dict[str, Any]:
    """永久抹除指定回收站文件 (限管理员)"""
    success = TrashService.permanently_delete(file_id)
    return {"success": success, "file_id": file_id}


@router.delete("", dependencies=[Depends(require_admin)])
async def empty_trash() -> Dict[str, Any]:
    """清空回收站 (限管理员)"""
    cleared_count = TrashService.empty_trash()
    return {"success": True, "cleared_count": cleared_count}
