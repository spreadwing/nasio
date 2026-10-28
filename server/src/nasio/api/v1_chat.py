from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, HTTPException
from nasio.core.security import verify_auth_token, require_admin
from nasio.services.chat_service import chat_service
from nasio.services.approval_service import approval_service
from nasio.services.transaction_service import transaction_service
from nasio.services.webhook_service import webhook_service

router = APIRouter(prefix="/chat", tags=["AI Assistant & Governance"])


# ==========================================
# 1. 内置 AI 聊天与服务端 Agent Loop 接口
# ==========================================

@router.get("/sessions", dependencies=[Depends(verify_auth_token)])
async def list_chat_sessions() -> Dict[str, Any]:
    """获取所有 AI 对话会话列表"""
    sessions = chat_service.list_sessions()
    return {"sessions": sessions, "total": len(sessions)}


@router.post("/sessions", dependencies=[Depends(verify_auth_token)])
async def create_chat_session(payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """创建新的 AI 对话会话"""
    title = (payload or {}).get("title", "新对话")
    sess = chat_service.create_session(title=title)
    return {"success": True, "session": sess.model_dump()}


@router.get("/sessions/{session_id}", dependencies=[Depends(verify_auth_token)])
async def get_chat_session(session_id: str) -> Dict[str, Any]:
    """获取指定会话的完整消息历史"""
    sess = chat_service.get_session(session_id)
    if not sess:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found")
    return {"session": sess.model_dump()}


@router.delete("/sessions/{session_id}", dependencies=[Depends(verify_auth_token)])
async def delete_chat_session(session_id: str) -> Dict[str, Any]:
    """删除指定对话会话"""
    deleted = chat_service.delete_session(session_id)
    return {"success": deleted, "session_id": session_id}


@router.post("/messages", dependencies=[Depends(verify_auth_token)])
async def send_chat_message(payload: Dict[str, Any]) -> Dict[str, Any]:
    """发送消息给服务端托管 AI Agent 并返回回复与工具调用轨迹"""
    content = (payload.get("content") or "").strip()
    session_id = payload.get("session_id")
    if not content:
        raise HTTPException(status_code=400, detail="Message content cannot be empty")
    res = await chat_service.send_message(content=content, session_id=session_id)
    return {"success": True, **res}


@router.post("/test-llm", dependencies=[Depends(require_admin)])
async def test_llm_connection(payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """测试大模型 API 连通性与延迟"""
    data = payload or {}
    return await chat_service.test_llm_connection(
        base_url=data.get("base_url"),
        api_key=data.get("api_key"),
        model=data.get("model"),
        provider=data.get("provider"),
    )


@router.post("/test-webhook", dependencies=[Depends(require_admin)])
async def test_webhook_connection(payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """测试主动事件 Webhook 连通性"""
    data = payload or {}
    return await webhook_service.test_webhook(
        url=data.get("url"),
        secret=data.get("secret"),
    )


# ==========================================
# 2. 高危操作人机协同审批接口 (Human-in-the-Loop)
# ==========================================

@router.get("/approvals", dependencies=[Depends(verify_auth_token)])
async def list_approvals(status: Optional[str] = None, limit: int = 50) -> Dict[str, Any]:
    """获取人机协同审批单列表"""
    items = approval_service.list_approvals(status_filter=status, limit=limit)
    return {
        "approvals": [i.model_dump() for i in items],
        "total": len(items),
        "pending_count": len([i for i in items if i.status == "PENDING"]),
    }


@router.post("/approvals/{approval_id}/decide", dependencies=[Depends(verify_auth_token)])
async def decide_approval(approval_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """批准或驳回 AI 的高危操作申请"""
    approved = bool(payload.get("approved", False))
    comment = str(payload.get("comment") or "")
    try:
        item = approval_service.decide_approval(
            approval_id=approval_id,
            approved=approved,
            comment=comment,
        )
        return {"success": True, "approval": item.model_dump()}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


# ==========================================
# 3. AI 批量操作事务查询与一键回滚接口 (Undo Engine)
# ==========================================

@router.get("/transactions", dependencies=[Depends(verify_auth_token)])
async def list_transactions(limit: int = 50) -> Dict[str, Any]:
    """获取 AI 近期批量文件操作事务列表"""
    items = transaction_service.list_transactions(limit=limit)
    return {
        "transactions": [
            {
                "transaction_id": t.transaction_id,
                "operation_type": t.operation_type,
                "summary": t.summary,
                "agent_task_id": t.agent_task_id,
                "status": t.status,
                "movements_count": len(t.movements),
                "trash_count": len(t.trash_ids),
                "created_at": t.created_at,
                "rolled_back_at": t.rolled_back_at,
            }
            for t in items
        ],
        "total": len(items),
    }


@router.post("/transactions/{transaction_id}/rollback", dependencies=[Depends(verify_auth_token)])
async def rollback_transaction(transaction_id: str) -> Dict[str, Any]:
    """一键原子回滚指定的 AI 批量操作事务"""
    try:
        res = transaction_service.rollback_transaction(transaction_id)
        return res
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
