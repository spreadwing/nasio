import os
import json
import time
import uuid
import shutil
import logging
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from nasio.core.config import CONFIG_PATH
from nasio.core.security import ensure_nas_compatible_dir, apply_nas_permissions
from nasio.services.trash_service import TrashService

logger = logging.getLogger("nasio.transaction")

DATA_DIR = os.path.dirname(CONFIG_PATH)
TRANSACTIONS_FILE = os.path.join(DATA_DIR, "action_transactions.json")


class FileMovementRecord(BaseModel):
    source: str
    destination: str


class ActionTransactionModel(BaseModel):
    transaction_id: str
    operation_type: str  # BATCH_ORGANIZE, BATCH_RENAME, FLATTEN_DIR, SERIES_ORGANIZE, CLEAN_RUBBISH, SAFE_DELETE
    summary: str
    agent_task_id: Optional[str] = None
    status: str = "APPLIED"  # APPLIED, ROLLED_BACK, PARTIAL_ROLLBACK
    movements: List[FileMovementRecord] = Field(default_factory=list)
    trash_ids: List[str] = Field(default_factory=list)
    created_at: float = Field(default_factory=time.time)
    rolled_back_at: Optional[float] = None


class TransactionService:
    """
    AI 操作事务化与一键回滚引擎 (Undo / Rollback Engine)：
    记录 AI 每次批量操作（重命名、移动归档、目录扁平化、多季整理、垃圾清理、软删除）的正逆向文件映射与回收站 ID，
    支持一键原子级逆向恢复（后悔药机制）。
    """

    _instance: Optional["TransactionService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._transactions: Dict[str, ActionTransactionModel] = {}
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(TRANSACTIONS_FILE):
                with open(TRANSACTIONS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        tx = ActionTransactionModel(**item)
                        self._transactions[tx.transaction_id] = tx
        except Exception as e:
            logger.warning("Failed to load transactions from %s: %s", TRANSACTIONS_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            tx_list = [t.model_dump() for t in self._transactions.values()]
            tx_list = sorted(tx_list, key=lambda x: x["created_at"], reverse=True)[:150]
            with open(TRANSACTIONS_FILE, "w", encoding="utf-8") as f:
                json.dump(tx_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save transactions to %s: %s", TRANSACTIONS_FILE, e)

    def record_transaction(
        self,
        operation_type: str,
        summary: str,
        movements: Optional[List[Dict[str, str]]] = None,
        trash_ids: Optional[List[str]] = None,
        agent_task_id: Optional[str] = None,
    ) -> Optional[ActionTransactionModel]:
        mov_records = []
        for m in (movements or []):
            src = m.get("source") or m.get("src")
            dst = m.get("destination") or m.get("dst")
            if src and dst and src != dst:
                mov_records.append(FileMovementRecord(source=src, destination=dst))

        valid_trash_ids = [tid for tid in (trash_ids or []) if tid]

        if not mov_records and not valid_trash_ids:
            return None

        tx_id = f"tx_{time.strftime('%Y%m%d')}_{uuid.uuid4().hex[:6]}"
        tx = ActionTransactionModel(
            transaction_id=tx_id,
            operation_type=operation_type,
            summary=summary,
            agent_task_id=agent_task_id,
            status="APPLIED",
            movements=mov_records,
            trash_ids=valid_trash_ids,
            created_at=time.time(),
        )
        self._transactions[tx_id] = tx
        self._save_to_disk()
        logger.info("Transaction recorded: [%s] %s (moves=%d, trash=%d)", tx_id, summary, len(mov_records), len(valid_trash_ids))
        return tx

    def list_transactions(self, limit: int = 50) -> List[ActionTransactionModel]:
        items = sorted(self._transactions.values(), key=lambda x: x.created_at, reverse=True)
        return items[:limit]

    def get_transaction(self, transaction_id: str) -> Optional[ActionTransactionModel]:
        return self._transactions.get(transaction_id)

    def rollback_transaction(self, transaction_id: str) -> Dict[str, Any]:
        tx = self._transactions.get(transaction_id)
        if not tx:
            raise ValueError(f"Transaction '{transaction_id}' not found")
        if tx.status == "ROLLED_BACK":
            return {
                "success": False,
                "transaction_id": transaction_id,
                "error": "该操作事务已经回滚过了，无需重复回滚",
            }

        restored_moves = 0
        restored_trash = 0
        errors = []

        # 1. 逆序回滚文件移动与重命名
        for mov in reversed(tx.movements):
            try:
                if os.path.exists(mov.destination):
                    src_parent = os.path.dirname(mov.source)
                    ensure_nas_compatible_dir(src_parent, reference_path=os.path.dirname(mov.destination))
                    shutil.move(mov.destination, mov.source)
                    apply_nas_permissions(mov.source, reference_path=src_parent)
                    restored_moves += 1
                else:
                    errors.append(f"目标文件不存在，无法移回: {mov.destination}")
            except Exception as e:
                errors.append(f"回滚移动失败 ({mov.destination} -> {mov.source}): {e}")

        # 2. 原路恢复关联的回收站软删除文件/目录
        for tid in reversed(tx.trash_ids):
            try:
                TrashService.restore_file(tid)
                restored_trash += 1
            except Exception as e:
                errors.append(f"恢复回收站条目失败 ({tid}): {e}")

        tx.status = "ROLLED_BACK" if not errors else "PARTIAL_ROLLBACK"
        tx.rolled_back_at = time.time()
        self._save_to_disk()

        return {
            "success": len(errors) == 0 or (restored_moves + restored_trash > 0),
            "transaction_id": transaction_id,
            "operation_type": tx.operation_type,
            "summary": tx.summary,
            "status": tx.status,
            "restored_movements_count": restored_moves,
            "restored_trash_count": restored_trash,
            "errors": errors,
        }


transaction_service = TransactionService()
