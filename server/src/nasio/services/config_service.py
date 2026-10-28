import os
import shutil
from typing import Dict, Any, List
from nasio.core.config import config_manager, AppConfig


class ConfigService:
    @staticmethod
    def get_config() -> AppConfig:
        return config_manager.get()

    @staticmethod
    def update_config(data: Dict[str, Any]) -> AppConfig:
        current = config_manager.get().model_dump()

        def _deep_merge(target: Dict[str, Any], src: Dict[str, Any]):
            for k, v in src.items():
                if k in target and isinstance(target[k], dict) and isinstance(v, dict):
                    _deep_merge(target[k], v)
                else:
                    # 若前端回传了脱敏占位符 ******，则保留原真实密钥不覆盖
                    if v == "******" and k in ("password", "rpc_secret", "api_key", "secret"):
                        continue
                    target[k] = v

        _deep_merge(current, data)
        new_config = AppConfig(**current)
        config_manager.save(new_config)
        return new_config

    @staticmethod
    def add_allowed_path(path: str) -> bool:
        real_path = os.path.realpath(os.path.expanduser(path))
        cfg = config_manager.get()
        if real_path not in cfg.storage.allowed_paths:
            cfg.storage.allowed_paths.append(real_path)
            config_manager.save(cfg)
            return True
        return False

    @staticmethod
    def remove_allowed_path(path: str) -> bool:
        real_path = os.path.realpath(os.path.expanduser(path))
        cfg = config_manager.get()
        if real_path in cfg.storage.allowed_paths:
            cfg.storage.allowed_paths.remove(real_path)
            config_manager.save(cfg)
            return True
        return False

    @staticmethod
    def get_storage_pools_status() -> List[Dict[str, Any]]:
        cfg = config_manager.get()
        results = []
        for path in cfg.storage.allowed_paths:
            if os.path.exists(path):
                try:
                    usage = shutil.disk_usage(path)
                    total_gb = round(usage.total / (1024 ** 3), 2)
                    used_gb = round(usage.used / (1024 ** 3), 2)
                    free_gb = round(usage.free / (1024 ** 3), 2)
                    used_percent = round((usage.used / usage.total) * 100, 1) if usage.total > 0 else 0
                    results.append({
                        "path": path,
                        "exists": True,
                        "total_gb": total_gb,
                        "used_gb": used_gb,
                        "free_gb": free_gb,
                        "used_percent": used_percent,
                    })
                except Exception as e:
                    results.append({
                        "path": path,
                        "exists": True,
                        "error": str(e)
                    })
            else:
                results.append({
                    "path": path,
                    "exists": False,
                    "error": "Directory not mounted or not found"
                })
        return results
