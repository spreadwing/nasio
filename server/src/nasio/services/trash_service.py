import os
import time
import json
import uuid
import shutil
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional
from nasio.core.config import get_app_config
from nasio.core.security import validate_sandbox_path, ensure_nas_compatible_dir, apply_nas_permissions

logger = logging.getLogger("nasio.trash")


class TrashService:
    @classmethod
    def _get_trash_dir(cls) -> str:
        cfg = get_app_config()
        trash_dir = os.path.realpath(os.path.expanduser(cfg.trash.trash_dir))
        ensure_nas_compatible_dir(trash_dir)
        return trash_dir

    @classmethod
    def _get_meta_file(cls) -> str:
        return os.path.join(cls._get_trash_dir(), "trash_metadata.json")

    @classmethod
    def _load_metadata(cls) -> Dict[str, Any]:
        meta_file = cls._get_meta_file()
        if os.path.exists(meta_file):
            try:
                with open(meta_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.error("Failed to read %s: %s", meta_file, e)
        return {}

    @classmethod
    def _save_metadata(cls, data: Dict[str, Any]):
        meta_file = cls._get_meta_file()
        try:
            with open(meta_file, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            apply_nas_permissions(meta_file)
        except Exception as e:
            logger.error("Failed to save %s: %s", meta_file, e)

    @classmethod
    def safe_delete(cls, paths: List[str], reason: str = "") -> List[Dict[str, Any]]:
        """软删除：将文件或目录移动到回收站分区，并记录元数据"""
        trash_dir = cls._get_trash_dir()
        date_folder = datetime.now().strftime("%Y-%m-%d")
        dest_folder = os.path.join(trash_dir, date_folder)
        ensure_nas_compatible_dir(dest_folder)

        meta = cls._load_metadata()
        results = []

        for p in paths:
            try:
                valid_path = validate_sandbox_path(p)
                if not os.path.exists(valid_path):
                    results.append({"path": p, "success": False, "error": "File or directory does not exist"})
                    continue

                file_id = uuid.uuid4().hex[:12]
                base_name = os.path.basename(valid_path)
                trash_filename = f"{file_id}_{base_name}"
                target_trash_path = os.path.join(dest_folder, trash_filename)

                # 获取大小
                is_dir = os.path.isdir(valid_path)
                size_bytes = 0
                if is_dir:
                    for root, _, files in os.walk(valid_path):
                        for f in files:
                            fp = os.path.join(root, f)
                            if os.path.exists(fp):
                                size_bytes += os.path.getsize(fp)
                else:
                    size_bytes = os.path.getsize(valid_path)

                # 物理移动
                shutil.move(valid_path, target_trash_path)

                # 记录元数据
                meta[file_id] = {
                    "id": file_id,
                    "original_path": valid_path,
                    "trash_path": target_trash_path,
                    "name": base_name,
                    "is_dir": is_dir,
                    "size_bytes": size_bytes,
                    "size_mb": round(size_bytes / (1024 * 1024), 2),
                    "deleted_at": datetime.now().isoformat(),
                    "reason": reason,
                }

                results.append({"path": p, "success": True, "trash_id": file_id})
            except Exception as e:
                logger.error("Failed to delete %s: %s", p, e)
                results.append({"path": p, "success": False, "error": str(e)})

        cls._save_metadata(meta)
        return results

    @classmethod
    def list_trash(
        cls, keyword: Optional[str] = None, page: int = 1, limit: int = 20
    ) -> Dict[str, Any]:
        """查询回收站列表（支持关键字筛选与分页）"""
        meta = cls._load_metadata()
        items = list(meta.values())

        if keyword:
            kw = keyword.lower()
            items = [item for item in items if kw in item.get("name", "").lower() or kw in item.get("original_path", "").lower()]

        items.sort(key=lambda x: x.get("deleted_at", ""), reverse=True)

        total = len(items)
        start = (page - 1) * limit
        end = start + limit
        page_items = items[start:end]

        return {
            "total": total,
            "page": page,
            "limit": limit,
            "items": page_items,
        }

    @classmethod
    def restore_file(cls, file_id: str, custom_target_dir: Optional[str] = None) -> Dict[str, Any]:
        """从回收站原路还原文件"""
        meta = cls._load_metadata()
        if file_id not in meta:
            raise FileNotFoundError(f"Trash item with ID '{file_id}' not found")

        item = meta[file_id]
        trash_path = item["trash_path"]

        if not os.path.exists(trash_path):
            del meta[file_id]
            cls._save_metadata(meta)
            raise FileNotFoundError(f"Underlying trash file '{trash_path}' is missing on disk")

        # 确定恢复目的地
        if custom_target_dir:
            valid_dest_dir = validate_sandbox_path(custom_target_dir)
            target_path = os.path.join(valid_dest_dir, item["name"])
        else:
            target_path = item["original_path"]

        target_parent = os.path.dirname(target_path)
        ensure_nas_compatible_dir(target_parent)

        # 检查重名冲突
        if os.path.exists(target_path):
            base, ext = os.path.splitext(item["name"])
            target_path = os.path.join(target_parent, f"{base}_restored_{int(time.time())}{ext}")

        shutil.move(trash_path, target_path)
        apply_nas_permissions(target_path, reference_path=target_parent)

        del meta[file_id]
        cls._save_metadata(meta)

        return {
            "success": True,
            "original_path": item["original_path"],
            "restored_path": target_path,
        }

    @classmethod
    def permanently_delete(cls, file_id: str) -> bool:
        """彻底抹除回收站文件"""
        meta = cls._load_metadata()
        if file_id not in meta:
            return False

        item = meta[file_id]
        trash_path = item["trash_path"]
        if os.path.exists(trash_path):
            if item.get("is_dir"):
                shutil.rmtree(trash_path, ignore_errors=True)
            else:
                os.remove(trash_path)

        del meta[file_id]
        cls._save_metadata(meta)
        return True

    @classmethod
    def empty_trash(cls) -> int:
        """清空整个回收站"""
        trash_dir = cls._get_trash_dir()
        meta = cls._load_metadata()
        count = len(meta)

        # 清除文件
        for file_id, item in meta.items():
            tp = item.get("trash_path")
            if tp and os.path.exists(tp):
                if item.get("is_dir"):
                    shutil.rmtree(tp, ignore_errors=True)
                else:
                    os.remove(tp)

        # 重置元数据
        cls._save_metadata({})
        return count
