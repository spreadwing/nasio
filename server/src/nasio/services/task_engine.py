import os
import time
import uuid
import asyncio
import logging
from enum import Enum
from typing import Dict, Any, Optional, List, Callable, Set
from pydantic import BaseModel, Field
from fastapi import WebSocket

logger = logging.getLogger("nasio.task_engine")


class TaskStatus(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    PAUSED = "PAUSED"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"


class TaskType(str, Enum):
    DOWNLOAD = "DOWNLOAD"
    DUPLICATE_SCAN = "DUPLICATE_SCAN"
    ARCHIVE_EXTRACT = "ARCHIVE_EXTRACT"
    BATCH_ORGANIZE = "BATCH_ORGANIZE"
    CUSTOM = "CUSTOM"


class TaskModel(BaseModel):
    task_id: str
    task_type: TaskType
    status: TaskStatus = TaskStatus.PENDING
    progress: float = 0.0  # 0.0 ~ 100.0
    created_at: float = Field(default_factory=time.time)
    updated_at: float = Field(default_factory=time.time)
    detail: Dict[str, Any] = Field(default_factory=dict)
    error: Optional[str] = None
    result: Optional[Any] = None


class AsyncTaskEngine:
    _instance: Optional["AsyncTaskEngine"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._tasks = {}
            cls._instance._cancel_flags = set()
            cls._instance._ws_clients = set()
        return cls._instance

    def __init__(self):
        self._tasks: Dict[str, TaskModel] = getattr(self, "_tasks", {})
        self._cancel_flags: Set[str] = getattr(self, "_cancel_flags", set())
        self._ws_clients: Set[WebSocket] = getattr(self, "_ws_clients", set())

    def create_task(self, task_type: TaskType, detail: Optional[Dict[str, Any]] = None) -> TaskModel:
        task_id = f"{task_type.value.lower()}_{uuid.uuid4().hex[:8]}"
        task = TaskModel(
            task_id=task_id,
            task_type=task_type,
            status=TaskStatus.RUNNING,
            detail=detail or {},
        )
        self._tasks[task_id] = task
        self.notify_change(task)
        logger.info("Task created: [%s] %s", task_id, task_type.value)
        return task

    def get_task(self, task_id: str) -> Optional[TaskModel]:
        t = self._tasks.get(task_id)
        if t:
            return t
        if task_id.startswith("qb_"):
            try:
                from nasio.services.downloader_service import DownloaderService
                qb_torrents = DownloaderService.get_qbittorrent_torrents(limit=200)
                for qt in qb_torrents:
                    if qt["task_id"] == task_id:
                        return TaskModel(**qt)
            except Exception:
                pass
        return None

    def list_tasks(self, limit: int = 100) -> List[TaskModel]:
        tasks = list(self._tasks.values())
        try:
            from nasio.services.downloader_service import DownloaderService
            qb_torrents = DownloaderService.get_qbittorrent_torrents(limit=limit)
            for qt in qb_torrents:
                if not any(t.task_id == qt["task_id"] for t in tasks):
                    try:
                        tasks.append(TaskModel(**qt))
                    except Exception as e:
                        logger.warning("Error parsing qb torrent: %s", e)
        except Exception as e:
            logger.warning("Failed to aggregate qbittorrent tasks: %s", e)

        sorted_tasks = sorted(tasks, key=lambda t: t.created_at, reverse=True)
        return sorted_tasks[:limit]

    def update_progress(
        self,
        task_id: str,
        progress: float,
        detail_updates: Optional[Dict[str, Any]] = None,
    ):
        task = self._tasks.get(task_id)
        if not task:
            return
        task.progress = min(100.0, max(0.0, round(progress, 2)))
        task.updated_at = time.time()
        if detail_updates:
            task.detail.update(detail_updates)
        self.notify_change(task)

        # 联动 Agent 任务监控
        agent_task_id = task.detail.get("agent_task_id")
        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.sync_progress_from_engine(agent_task_id, task_id, task.progress, task.detail)
            except Exception as e:
                logger.debug("Failed to sync progress to agent task: %s", e)

    def complete_task(self, task_id: str, result: Optional[Any] = None):
        task = self._tasks.get(task_id)
        if not task:
            return
        task.status = TaskStatus.COMPLETED
        task.progress = 100.0
        task.result = result
        task.updated_at = time.time()
        self.notify_change(task)
        logger.info("Task completed: [%s]", task_id)

        # 联动 Agent 任务监控
        agent_task_id = task.detail.get("agent_task_id")
        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.sync_completion_from_engine(agent_task_id, task_id, result=result)
            except Exception as e:
                logger.debug("Failed to sync completion to agent task: %s", e)

        # 触发主动事件 Webhook 广播
        try:
            from nasio.services.webhook_service import webhook_service
            webhook_service.emit_event(
                event_type="TASK_COMPLETED",
                summary=f"后台任务已完成: [{task.task_type.value}] {task_id}",
                data=task.model_dump(),
                suggested_prompt=f"NAS 后台任务 {task_id} ({task.task_type.value}) 已执行完成，详情: {task.detail}。请检查输出目录并执行后续整理或校验。",
            )
        except Exception as e:
            logger.debug("Failed to emit task completion webhook: %s", e)


    def fail_task(self, task_id: str, error_message: str):
        task = self._tasks.get(task_id)
        if not task:
            return
        task.status = TaskStatus.FAILED
        task.error = error_message
        task.updated_at = time.time()
        self.notify_change(task)
        logger.error("Task failed: [%s] Error: %s", task_id, error_message)

        # 联动 Agent 任务监控
        agent_task_id = task.detail.get("agent_task_id")
        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.sync_failure_from_engine(agent_task_id, task_id, error_message=error_message)
            except Exception as e:
                logger.debug("Failed to sync failure to agent task: %s", e)

    def cancel_task(self, task_id: str, delete_files: bool = False) -> bool:
        if task_id.startswith("qb_"):
            try:
                from nasio.services.downloader_service import DownloaderService
                return DownloaderService.delete_qbittorrent_torrent(task_id[3:], delete_files=delete_files)
            except Exception as e:
                logger.error("Failed to cancel qbittorrent task %s: %s", task_id, e)
                return False
        task = self._tasks.get(task_id)
        if not task or task.status in [TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED]:
            return False
        self._cancel_flags.add(task_id)
        task.status = TaskStatus.CANCELLED
        task.updated_at = time.time()
        self.notify_change(task)
        logger.info("Task cancelled: [%s] (delete_files=%s)", task_id, delete_files)
        return True

    def is_cancelled(self, task_id: str) -> bool:
        return task_id in self._cancel_flags

    def clear_failed_tasks(self, delete_files: bool = False) -> int:
        """清空所有失败任务（包括本地任务和 qBittorrent 错误任务）"""
        cleared_count = 0
        failed_ids = [tid for tid, t in self._tasks.items() if t.status == TaskStatus.FAILED]
        for tid in failed_ids:
            task = self._tasks.pop(tid, None)
            if task and delete_files:
                saved_file = task.detail.get("saved_file")
                if saved_file and os.path.exists(saved_file):
                    try:
                        os.remove(saved_file)
                    except Exception as e:
                        logger.warning("Failed to delete file %s for task %s: %s", saved_file, tid, e)
            cleared_count += 1

        try:
            from nasio.services.downloader_service import DownloaderService
            client = DownloaderService.get_qb_client()
            if client:
                error_hashes = []
                for t in client.torrents_info():
                    if t.get("state") in ["error", "missingFiles"]:
                        error_hashes.append(t.get("hash"))
                if error_hashes:
                    client.torrents_delete(torrent_hashes="|".join(error_hashes), delete_files=delete_files)
                    cleared_count += len(error_hashes)
        except Exception as e:
            logger.warning("Failed to clear failed torrents in qbittorrent: %s", e)

        logger.info("Cleared %d failed tasks (delete_files=%s)", cleared_count, delete_files)
        return cleared_count

    # WebSocket 广播
    def register_ws(self, ws: WebSocket):
        self._ws_clients.add(ws)
        if not hasattr(self, "_sync_task") or self._sync_task is None or self._sync_task.done():
            self._sync_task = asyncio.create_task(self._periodic_ws_sync_loop())

    async def _periodic_ws_sync_loop(self):
        """定期向 WebSocket 客户端广播活跃任务状态"""
        while self._ws_clients:
            try:
                await asyncio.sleep(2)
                if not self._ws_clients:
                    break
                from nasio.services.downloader_service import DownloaderService
                qb_torrents = DownloaderService.get_qbittorrent_torrents(limit=50)
                for qt in qb_torrents:
                    if qt["status"] in ["RUNNING", "PAUSED", "PENDING"] or qt["detail"].get("speed", "0 B/s") != "0 B/s":
                        message = {
                            "event": "TASK_UPDATE",
                            "data": qt,
                        }
                        await self._broadcast(message)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.debug("Error in ws sync loop: %s", e)

    def unregister_ws(self, ws: WebSocket):
        self._ws_clients.discard(ws)

    def notify_change(self, task: TaskModel):
        if not self._ws_clients:
            return
        message = {
            "event": "TASK_UPDATE",
            "data": task.model_dump(),
        }
        # 异步广播
        asyncio.create_task(self._broadcast(message))

    async def _broadcast(self, message: dict):
        dead_clients = set()
        for ws in self._ws_clients:
            try:
                await ws.send_json(message)
            except Exception:
                dead_clients.add(ws)
        self._ws_clients.difference_update(dead_clients)


task_engine = AsyncTaskEngine()
