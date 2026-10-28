import os
import yaml
import logging
from typing import List, Optional
from pydantic import BaseModel, Field

logger = logging.getLogger("nasio.config")

CONFIG_PATH = os.environ.get("CONFIG_PATH", os.path.join(os.getcwd(), "data", "config.yaml"))


class StorageConfig(BaseModel):
    allowed_paths: List[str] = Field(
        default_factory=lambda: ["/volume1/Download", "/volume1/Media"]
    )
    max_search_depth: int = 8
    max_batch_operation_files: int = 500


class TrashConfig(BaseModel):
    trash_dir: str = "/volume1/.trash"
    retention_days: int = 30
    max_capacity_gb: int = 150
    enable_audit_log: bool = True


class QBittorrentConfig(BaseModel):
    enabled: bool = False
    url: str = "http://localhost:8080"
    username: str = "admin"
    password: str = "adminadmin"
    default_category: str = "Nasio"
    auto_stop_seeding: bool = False


class Aria2Config(BaseModel):
    enabled: bool = False
    rpc_url: str = "http://localhost:6800/jsonrpc"
    rpc_secret: str = ""


class DownloadersConfig(BaseModel):
    default_engine: str = "auto"
    qbittorrent: QBittorrentConfig = Field(default_factory=QBittorrentConfig)
    aria2: Aria2Config = Field(default_factory=Aria2Config)


class BuiltinEngineConfig(BaseModel):
    max_threads_per_download: int = 8
    ytdlp_format: str = "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
    global_download_rate_limit: int = 0


class LLMConfig(BaseModel):
    enabled: bool = False
    provider: str = "openai_compatible"
    base_url: str = "https://api.deepseek.com/v1"
    api_key: str = ""
    model: str = "deepseek-chat"
    temperature: float = 0.2
    max_tool_rounds: int = 8
    system_prompt: str = (
        "你是 Nasio（绿联 NAS 智能中枢与资产管家）的内置 AI 副驾驶。"
        "你可以通过调用工具感知 NAS 目录结构摘要、检索文件、清理垃圾广告、整理剧集与文件、管理下载及 RSS 订阅。"
        "在执行大规模删除或移动前，请优先使用 dry_run=True 预览或发起人机审批，确保用户数据安全。"
    )


class WebhookConfig(BaseModel):
    enabled: bool = False
    url: str = ""
    secret: str = ""
    events: List[str] = Field(
        default_factory=lambda: [
            "TASK_COMPLETED",
            "RSS_MATCHED",
            "APPROVAL_REQUESTED",
            "DISK_LOW",
        ]
    )


class AppConfig(BaseModel):
    storage: StorageConfig = Field(default_factory=StorageConfig)
    trash: TrashConfig = Field(default_factory=TrashConfig)
    downloaders: DownloadersConfig = Field(default_factory=DownloadersConfig)
    builtin_engine: BuiltinEngineConfig = Field(default_factory=BuiltinEngineConfig)
    llm: LLMConfig = Field(default_factory=LLMConfig)
    webhook: WebhookConfig = Field(default_factory=WebhookConfig)


class ConfigManager:
    _instance: Optional["ConfigManager"] = None
    _config: AppConfig

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._config = AppConfig()
            cls._instance.load()
        return cls._instance

    def load(self) -> AppConfig:
        if os.path.exists(CONFIG_PATH):
            try:
                with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f) or {}
                self._config = AppConfig(**data)
                logger.info("Configuration successfully loaded from %s", CONFIG_PATH)
            except Exception as e:
                logger.error("Failed to parse %s, using defaults. Error: %s", CONFIG_PATH, e)
        else:
            logger.warning("Config file not found at %s, creating default config", CONFIG_PATH)
            self.save(self._config)
        return self._config

    def get(self) -> AppConfig:
        return self._config

    def save(self, config: AppConfig) -> bool:
        try:
            os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                yaml.safe_dump(config.model_dump(), f, allow_unicode=True, sort_keys=False)
            self._config = config
            logger.info("Configuration saved to %s", CONFIG_PATH)
            return True
        except Exception as e:
            logger.error("Failed to write %s: %s", CONFIG_PATH, e)
            return False


config_manager = ConfigManager()


def get_app_config() -> AppConfig:
    return config_manager.get()
