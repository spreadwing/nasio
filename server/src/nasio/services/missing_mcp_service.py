import os
import json
import time
import uuid
import logging
from typing import List, Optional
from pydantic import BaseModel, Field
from nasio.core.config import CONFIG_PATH

logger = logging.getLogger("nasio.missing_mcp")

DATA_DIR = os.path.dirname(CONFIG_PATH)
MISSING_MCP_FILE = os.path.join(DATA_DIR, "missing_mcp_tools.json")


class MissingMcpToolModel(BaseModel):
    id: str = Field(default_factory=lambda: f"mcp_req_{uuid.uuid4().hex[:8]}")
    tool_name: str
    description: str
    suggested_parameters: Optional[str] = None
    scenario: Optional[str] = None
    agent_task_id: Optional[str] = None
    created_at: float = Field(default_factory=time.time)


class MissingMcpToolService:
    _instance: Optional["MissingMcpToolService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._items = {}
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(MISSING_MCP_FILE):
                with open(MISSING_MCP_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        model = MissingMcpToolModel(**item)
                        self._items[model.id] = model
                logger.info("Loaded %d missing MCP tool requests from %s", len(self._items), MISSING_MCP_FILE)
        except Exception as e:
            logger.warning("Failed to load missing MCP tools from %s: %s", MISSING_MCP_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            item_list = [item.model_dump() for item in self._items.values()]
            # 保存最近 300 条上报
            item_list = sorted(item_list, key=lambda x: x["created_at"], reverse=True)[:300]
            with open(MISSING_MCP_FILE, "w", encoding="utf-8") as f:
                json.dump(item_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save missing MCP tools to %s: %s", MISSING_MCP_FILE, e)

    def report_missing_tool(
        self,
        tool_name: str,
        description: str,
        suggested_parameters: Optional[str] = None,
        scenario: Optional[str] = None,
        agent_task_id: Optional[str] = None,
    ) -> MissingMcpToolModel:
        model = MissingMcpToolModel(
            tool_name=tool_name,
            description=description,
            suggested_parameters=suggested_parameters,
            scenario=scenario,
            agent_task_id=agent_task_id,
        )
        self._items[model.id] = model
        self._save_to_disk()
        logger.info("Reported missing MCP tool: [%s] %s", model.id, tool_name)
        return model

    def list_missing_tools(self, limit: int = 100) -> List[MissingMcpToolModel]:
        items = list(self._items.values())
        items = sorted(items, key=lambda x: x.created_at, reverse=True)
        return items[:limit]

    def delete_missing_tool(self, req_id: str) -> bool:
        if req_id in self._items:
            del self._items[req_id]
            self._save_to_disk()
            logger.info("Deleted missing MCP tool request: [%s]", req_id)
            return True
        return False

    def clear_all(self) -> int:
        count = len(self._items)
        self._items.clear()
        self._save_to_disk()
        logger.info("Cleared all %d missing MCP tool requests", count)
        return count


missing_mcp_service = MissingMcpToolService()
