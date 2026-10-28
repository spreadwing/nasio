from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, Query, HTTPException, status
from nasio.core.security import verify_auth_token
from nasio.services.agent_task_service import agent_task_service, AgentTaskModel

router = APIRouter(prefix="/agent-tasks", tags=["Agent Tasks"])


class StartAgentTaskRequest(BaseModel):
    title: str
    description: str = ""
    total_steps: int = 1
    agent_task_id: Optional[str] = None


class ReportStepRequest(BaseModel):
    step_name: str
    step_index: Optional[int] = None
    progress: Optional[float] = None
    log_message: str = ""
    status: str = "COMPLETED"


class CompleteTaskRequest(BaseModel):
    result: Optional[Any] = None
    prompt_template: Optional[str] = None


class FailTaskRequest(BaseModel):
    error: str


@router.post("", dependencies=[Depends(verify_auth_token)], response_model=AgentTaskModel)
async def start_agent_task(req: StartAgentTaskRequest) -> AgentTaskModel:
    """创建并启动一个 AI Agent 复合长任务"""
    return agent_task_service.start_task(
        title=req.title,
        description=req.description,
        total_steps=req.total_steps,
        agent_task_id=req.agent_task_id,
    )


@router.get("", dependencies=[Depends(verify_auth_token)], response_model=List[AgentTaskModel])
async def list_agent_tasks(
    status: Optional[str] = Query(None, description="RUNNING / COMPLETED / FAILED / CANCELLED"),
    limit: int = Query(50, ge=1, le=200),
) -> List[AgentTaskModel]:
    """获取所有 AI Agent 复合任务列表"""
    return agent_task_service.list_tasks(status=status, limit=limit)


@router.get("/{agent_task_id}", dependencies=[Depends(verify_auth_token)], response_model=AgentTaskModel)
async def get_agent_task(agent_task_id: str) -> AgentTaskModel:
    """获取指定 Agent 任务的多步执行明细与时间轴"""
    task = agent_task_service.get_task(agent_task_id)
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent task '{agent_task_id}' not found",
        )
    return task


@router.post("/{agent_task_id}/step", dependencies=[Depends(verify_auth_token)], response_model=AgentTaskModel)
async def report_agent_task_step(agent_task_id: str, req: ReportStepRequest) -> AgentTaskModel:
    """汇报阶段性操作进展与执行日志"""
    task = agent_task_service.report_step(
        agent_task_id=agent_task_id,
        step_name=req.step_name,
        step_index=req.step_index,
        progress=req.progress,
        log_message=req.log_message,
        status=req.status,
    )
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent task '{agent_task_id}' not found",
        )
    return task


@router.post("/{agent_task_id}/complete", dependencies=[Depends(verify_auth_token)], response_model=AgentTaskModel)
async def complete_agent_task(agent_task_id: str, req: CompleteTaskRequest) -> AgentTaskModel:
    """标记 Agent 任务执行成功"""
    task = agent_task_service.complete_task(
        agent_task_id=agent_task_id,
        result=req.result,
        prompt_template=req.prompt_template,
    )
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent task '{agent_task_id}' not found",
        )
    return task


@router.post("/{agent_task_id}/fail", dependencies=[Depends(verify_auth_token)], response_model=AgentTaskModel)
async def fail_agent_task(agent_task_id: str, req: FailTaskRequest) -> AgentTaskModel:
    """标记 Agent 任务执行失败"""
    task = agent_task_service.fail_task(agent_task_id=agent_task_id, error_message=req.error)
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent task '{agent_task_id}' not found",
        )
    return task


@router.post("/{agent_task_id}/cancel", dependencies=[Depends(verify_auth_token)])
async def cancel_agent_task(agent_task_id: str) -> Dict[str, Any]:
    """取消 Agent 任务"""
    success = agent_task_service.cancel_task(agent_task_id)
    return {"agent_task_id": agent_task_id, "cancelled": success}


@router.delete("", dependencies=[Depends(verify_auth_token)])
async def clear_finished_agent_tasks() -> Dict[str, Any]:
    """批量清空已结束（已完成/已失败/已取消）的 Agent 任务记录"""
    cleared_count = agent_task_service.clear_finished_tasks()
    return {"cleared_count": cleared_count}


@router.delete("/{agent_task_id}", dependencies=[Depends(verify_auth_token)])
async def delete_agent_task(agent_task_id: str) -> Dict[str, Any]:
    """删除单条已结束的 Agent 任务记录"""
    task = agent_task_service.get_task(agent_task_id)
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent task '{agent_task_id}' not found",
        )
    try:
        agent_task_service.delete_task(agent_task_id)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    return {"agent_task_id": agent_task_id, "deleted": True}

