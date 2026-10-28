import os
import json
import time
import uuid
import asyncio
import logging
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from nasio.core.config import CONFIG_PATH
from nasio.services.task_engine import task_engine
from nasio.services.webhook_service import webhook_service

logger = logging.getLogger("nasio.approval")

DATA_DIR = os.path.dirname(CONFIG_PATH)
APPROVALS_FILE = os.path.join(DATA_DIR, "approvals.json")


class ApprovalItemModel(BaseModel):
    approval_id: str
    title: str
    description: str = ""
    diff_preview: str = ""
    agent_task_id: Optional[str] = None
    status: str = "PENDING"  # PENDING, APPROVED, REJECTED, EXPIRED
    decision_comment: str = ""
    created_at: float = Field(default_factory=time.time)
    decided_at: Optional[float] = None


class ApprovalService:
    """
    AI 高危操作的人机协同审批服务 (Human-in-the-Loop)：
    当 AI 准备执行大规模删除、大范围目录重组或洗版替换时，创建审批单并实时推送到 Flutter 客户端，
    等待人工确认“同意”或“驳回（附修改意见）”后再继续执行。
    """

    _instance: Optional["ApprovalService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._approvals: Dict[str, ApprovalItemModel] = {}
            cls._instance._events: Dict[str, asyncio.Event] = {}
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(APPROVALS_FILE):
                with open(APPROVALS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        apr = ApprovalItemModel(**item)
                        self._approvals[apr.approval_id] = apr
        except Exception as e:
            logger.warning("Failed to load approvals from %s: %s", APPROVALS_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            apr_list = [a.model_dump() for a in self._approvals.values()]
            apr_list = sorted(apr_list, key=lambda x: x["created_at"], reverse=True)[:100]
            with open(APPROVALS_FILE, "w", encoding="utf-8") as f:
                json.dump(apr_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save approvals to %s: %s", APPROVALS_FILE, e)

    def _broadcast_change(self, item: ApprovalItemModel):
        self._save_to_disk()
        msg = {
            "event": "APPROVAL_UPDATE",
            "data": item.model_dump(),
        }
        try:
            loop = asyncio.get_running_loop()
            if loop.is_running():
                asyncio.create_task(task_engine._broadcast(msg))
        except RuntimeError:
            pass

    def create_approval(
        self,
        title: str,
        description: str = "",
        diff_preview: str = "",
        agent_task_id: Optional[str] = None,
    ) -> ApprovalItemModel:
        apr_id = f"apr_{time.strftime('%Y%m%d')}_{uuid.uuid4().hex[:6]}"
        item = ApprovalItemModel(
            approval_id=apr_id,
            title=title,
            description=description,
            diff_preview=diff_preview,
            agent_task_id=agent_task_id,
            status="PENDING",
            created_at=time.time(),
        )
        self._approvals[apr_id] = item
        self._events[apr_id] = asyncio.Event()
        self._broadcast_change(item)

        webhook_service.emit_event(
            event_type="APPROVAL_REQUESTED",
            summary=f"AI 请求人工审批: {title}",
            data=item.model_dump(),
            suggested_prompt=f"AI 发起高危操作审批 [{apr_id}]: {title}，详情: {description}。请前往 Nasio 客户端确认。",
        )
        logger.info("Approval created: [%s] %s", apr_id, title)
        return item

    async def wait_for_decision(self, approval_id: str, timeout_seconds: int = 120) -> ApprovalItemModel:
        item = self._approvals.get(approval_id)
        if not item:
            raise ValueError(f"Approval '{approval_id}' not found")
        if item.status != "PENDING":
            return item

        ev = self._events.setdefault(approval_id, asyncio.Event())
        try:
            await asyncio.wait_for(ev.wait(), timeout=max(5, min(timeout_seconds, 600)))
        except asyncio.TimeoutError:
            if item.status == "PENDING":
                item.status = "EXPIRED"
                item.decided_at = time.time()
                self._broadcast_change(item)
        return self._approvals[approval_id]

    def decide_approval(
        self,
        approval_id: str,
        approved: bool,
        comment: str = "",
    ) -> ApprovalItemModel:
        item = self._approvals.get(approval_id)
        if not item:
            raise ValueError(f"Approval '{approval_id}' not found")

        item.status = "APPROVED" if approved else "REJECTED"
        item.decision_comment = comment.strip()
        item.decided_at = time.time()
        self._broadcast_change(item)

        ev = self._events.get(approval_id)
        if ev:
            ev.set()

        logger.info("Approval decided: [%s] -> %s (%s)", approval_id, item.status, comment)
        return item

    def list_approvals(self, status_filter: Optional[str] = None, limit: int = 50) -> List[ApprovalItemModel]:
        items = list(self._approvals.values())
        if status_filter:
            sf = status_filter.upper()
            items = [a for a in items if a.status == sf]
        items.sort(key=lambda x: x.created_at, reverse=True)
        return items[:limit]

    def get_approval(self, approval_id: str) -> Optional[ApprovalItemModel]:
        return self._approvals.get(approval_id)


approval_service = ApprovalService()
