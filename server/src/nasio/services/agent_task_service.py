import os
import json
import time
import uuid
import logging
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from nasio.core.config import CONFIG_PATH
from nasio.services.task_engine import task_engine

logger = logging.getLogger("nasio.agent_task")

DATA_DIR = os.path.dirname(CONFIG_PATH)
AGENT_TASKS_FILE = os.path.join(DATA_DIR, "agent_tasks.json")


class AgentTaskStep(BaseModel):
    step_index: int
    step_name: str
    status: str = "COMPLETED"  # PENDING, RUNNING, COMPLETED, FAILED
    progress: float = 100.0
    log_message: str = ""
    timestamp: float = Field(default_factory=time.time)


class AgentSubAction(BaseModel):
    action_type: str  # DOWNLOAD, FILE_ORGANIZE, DUPLICATE_SCAN, TRASH_DELETE, CUSTOM
    action_id: str
    summary: str
    status: str = "COMPLETED"
    timestamp: float = Field(default_factory=time.time)


class AgentTaskModel(BaseModel):
    agent_task_id: str
    title: str
    description: str = ""
    status: str = "RUNNING"  # RUNNING, COMPLETED, FAILED, CANCELLED
    progress: float = 0.0
    total_steps: int = 1
    current_step: int = 1
    steps: List[AgentTaskStep] = Field(default_factory=list)
    sub_actions: List[AgentSubAction] = Field(default_factory=list)
    result: Optional[Any] = None
    error: Optional[str] = None
    prompt_template: Optional[str] = None
    created_at: float = Field(default_factory=time.time)
    updated_at: float = Field(default_factory=time.time)


class AgentTaskService:
    _instance: Optional["AgentTaskService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._tasks = {}
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(AGENT_TASKS_FILE):
                with open(AGENT_TASKS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        task = AgentTaskModel(**item)
                        # 自愈历史脏数据：防止 current_step > total_steps
                        if task.current_step > task.total_steps:
                            task.total_steps = task.current_step
                        if len(task.steps) > task.total_steps:
                            task.total_steps = len(task.steps)
                        self._tasks[task.agent_task_id] = task
                logger.info("Loaded %d agent tasks from %s", len(self._tasks), AGENT_TASKS_FILE)
        except Exception as e:
            logger.warning("Failed to load agent tasks from %s: %s", AGENT_TASKS_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            task_list = [t.model_dump() for t in self._tasks.values()]
            # 保存最近 200 个任务
            task_list = sorted(task_list, key=lambda x: x["created_at"], reverse=True)[:200]
            with open(AGENT_TASKS_FILE, "w", encoding="utf-8") as f:
                json.dump(task_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save agent tasks to %s: %s", AGENT_TASKS_FILE, e)

    def _broadcast_change(self, task: AgentTaskModel):
        self._save_to_disk()
        msg = {
            "event": "AGENT_TASK_UPDATE",
            "data": task.model_dump(),
        }
        # 借用 task_engine 广播通道
        try:
            import asyncio
            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = None
            if loop and loop.is_running():
                asyncio.create_task(task_engine._broadcast(msg))
        except Exception as e:
            logger.debug("Failed to broadcast agent task update: %s", e)

    def start_task(
        self,
        title: str,
        description: str = "",
        total_steps: int = 1,
        agent_task_id: Optional[str] = None,
    ) -> AgentTaskModel:
        if not agent_task_id:
            agent_task_id = f"agent_{time.strftime('%Y%m%d')}_{uuid.uuid4().hex[:6]}"

        task = AgentTaskModel(
            agent_task_id=agent_task_id,
            title=title,
            description=description,
            status="RUNNING",
            progress=0.0,
            total_steps=max(1, total_steps),
            current_step=1,
            steps=[],
            sub_actions=[],
            created_at=time.time(),
            updated_at=time.time(),
        )
        self._tasks[agent_task_id] = task
        self._broadcast_change(task)
        logger.info("Agent task started: [%s] %s", agent_task_id, title)
        return task

    def report_step(
        self,
        agent_task_id: str,
        step_name: str,
        step_index: Optional[int] = None,
        progress: Optional[float] = None,
        log_message: str = "",
        status: str = "COMPLETED",
    ) -> Optional[AgentTaskModel]:
        task = self._tasks.get(agent_task_id)
        if not task:
            # 允许自启动
            task = self.start_task(title=step_name, description="Auto-registered agent task", agent_task_id=agent_task_id)

        idx = step_index if step_index is not None else len(task.steps) + 1
        task.current_step = idx
        if idx > task.total_steps:
            task.total_steps = idx
        if progress is not None:
            task.progress = min(100.0, max(0.0, round(progress, 1)))
        else:
            task.progress = min(100.0, round((idx / max(task.total_steps, 1)) * 100.0, 1))

        step = AgentTaskStep(
            step_index=idx,
            step_name=step_name,
            status=status,
            progress=task.progress,
            log_message=log_message,
            timestamp=time.time(),
        )
        task.steps.append(step)
        task.updated_at = time.time()
        self._broadcast_change(task)
        logger.info("Agent task [%s] step %d: %s", agent_task_id, idx, step_name)
        return task

    def add_sub_action(
        self,
        agent_task_id: str,
        action_type: str,
        action_id: str,
        summary: str,
        status: str = "COMPLETED",
    ) -> bool:
        task = self._tasks.get(agent_task_id)
        if not task:
            return False

        # 若已存在则更新状态与描述，避免重复追加
        for sa in task.sub_actions:
            if sa.action_id == action_id:
                sa.status = status
                sa.summary = summary
                task.updated_at = time.time()
                self._broadcast_change(task)
                return True

        action = AgentSubAction(
            action_type=action_type,
            action_id=action_id,
            summary=summary,
            status=status,
            timestamp=time.time(),
        )
        task.sub_actions.append(action)
        task.updated_at = time.time()
        self._broadcast_change(task)
        return True

    def update_sub_action_status(
        self,
        agent_task_id: str,
        action_id: str,
        status: str,
        summary: Optional[str] = None,
    ) -> bool:
        task = self._tasks.get(agent_task_id)
        if not task:
            return False
        found = False
        for sa in task.sub_actions:
            if sa.action_id == action_id:
                sa.status = status
                if summary:
                    sa.summary = summary
                found = True
                break
        if found:
            task.updated_at = time.time()
            self._broadcast_change(task)
        return found

    def sync_progress_from_engine(
        self,
        agent_task_id: str,
        task_id: str,
        progress: float,
        detail: Optional[Dict[str, Any]] = None,
    ):
        """来自 TaskEngine 的异步长任务进度深度联动"""
        task = self._tasks.get(agent_task_id)
        if not task or task.status != "RUNNING":
            return
        for sa in task.sub_actions:
            if sa.action_id == task_id and sa.status != "RUNNING":
                sa.status = "RUNNING"
        # 单步或自动托管任务，同步主任务百分比
        if task.total_steps <= 1 or task.description.startswith("[自动托管]"):
            task.progress = min(99.0, max(task.progress, round(progress, 1)))
        task.updated_at = time.time()
        self._broadcast_change(task)

    def sync_completion_from_engine(
        self,
        agent_task_id: str,
        task_id: str,
        result: Optional[Any] = None,
    ):
        """来自 TaskEngine 的异步长任务成功完成联动"""
        task = self._tasks.get(agent_task_id)
        if not task:
            return
        for sa in task.sub_actions:
            if sa.action_id == task_id:
                sa.status = "COMPLETED"
        task.updated_at = time.time()

        if task.total_steps <= 1 or task.description.startswith("[自动托管]"):
            self.report_step(
                agent_task_id=agent_task_id,
                step_name="底层异步任务执行完成",
                status="COMPLETED",
                progress=100.0,
            )
            self.complete_task(agent_task_id, result=result)
        else:
            self._broadcast_change(task)

    def sync_failure_from_engine(
        self,
        agent_task_id: str,
        task_id: str,
        error_message: str,
    ):
        """来自 TaskEngine 的异步长任务失败联动"""
        task = self._tasks.get(agent_task_id)
        if not task:
            return
        for sa in task.sub_actions:
            if sa.action_id == task_id:
                sa.status = "FAILED"
        task.updated_at = time.time()

        if task.total_steps <= 1 or task.description.startswith("[自动托管]"):
            self.report_step(
                agent_task_id=agent_task_id,
                step_name="底层异步任务异常中断",
                status="FAILED",
                log_message=error_message,
            )
            self.fail_task(agent_task_id, error_message)
        else:
            self._broadcast_change(task)

    def complete_task(
        self,
        agent_task_id: str,
        result: Optional[Any] = None,
        prompt_template: Optional[str] = None,
    ) -> Optional[AgentTaskModel]:
        task = self._tasks.get(agent_task_id)
        if not task:
            return None
        task.status = "COMPLETED"
        task.progress = 100.0
        if task.total_steps < task.current_step:
            task.total_steps = task.current_step
        if len(task.steps) > task.total_steps:
            task.total_steps = len(task.steps)
        task.result = result
        if prompt_template:
            task.prompt_template = prompt_template
        task.updated_at = time.time()
        self._broadcast_change(task)
        logger.info("Agent task completed: [%s]", agent_task_id)
        return task

    def fail_task(self, agent_task_id: str, error_message: str) -> Optional[AgentTaskModel]:
        task = self._tasks.get(agent_task_id)
        if not task:
            return None
        task.status = "FAILED"
        task.error = error_message
        task.updated_at = time.time()
        self._broadcast_change(task)
        logger.error("Agent task failed: [%s] %s", agent_task_id, error_message)
        return task

    def cancel_task(self, agent_task_id: str) -> bool:
        task = self._tasks.get(agent_task_id)
        if not task or task.status in ["COMPLETED", "FAILED", "CANCELLED"]:
            return False
        task.status = "CANCELLED"
        task.updated_at = time.time()
        self._broadcast_change(task)
        logger.info("Agent task cancelled: [%s]", agent_task_id)
        return True

    def list_tasks(self, status: Optional[str] = None, limit: int = 50) -> List[AgentTaskModel]:
        tasks = list(self._tasks.values())
        if status:
            tasks = [t for t in tasks if t.status.upper() == status.upper()]
        sorted_tasks = sorted(tasks, key=lambda t: t.created_at, reverse=True)
        return sorted_tasks[:limit]

    def get_task(self, agent_task_id: str) -> Optional[AgentTaskModel]:
        return self._tasks.get(agent_task_id)

    def delete_task(self, agent_task_id: str) -> bool:
        task = self._tasks.get(agent_task_id)
        if not task:
            return False
        if task.status == "RUNNING":
            raise ValueError(f"Cannot delete running agent task '{agent_task_id}'. Please cancel or wait for it to finish.")
        del self._tasks[agent_task_id]
        self._save_to_disk()
        logger.info("Agent task deleted: [%s]", agent_task_id)
        try:
            import asyncio
            msg = {
                "event": "AGENT_TASK_DELETED",
                "data": {"agent_task_id": agent_task_id},
            }
            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = None
            if loop and loop.is_running():
                asyncio.create_task(task_engine._broadcast(msg))
        except Exception as e:
            logger.debug("Failed to broadcast agent task deletion: %s", e)
        return True

    def clear_finished_tasks(self) -> int:
        to_delete = [
            tid for tid, t in self._tasks.items()
            if t.status in ["COMPLETED", "FAILED", "CANCELLED"]
        ]
        if not to_delete:
            return 0
        for tid in to_delete:
            del self._tasks[tid]
        self._save_to_disk()
        logger.info("Cleared %d finished agent tasks", len(to_delete))
        try:
            import asyncio
            msg = {
                "event": "AGENT_TASKS_CLEARED",
                "data": {"deleted_ids": to_delete},
            }
            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = None
            if loop and loop.is_running():
                asyncio.create_task(task_engine._broadcast(msg))
        except Exception as e:
            logger.debug("Failed to broadcast agent tasks cleared: %s", e)
        return len(to_delete)


agent_task_service = AgentTaskService()
