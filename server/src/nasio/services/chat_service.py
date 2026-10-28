import os
import json
import time
import uuid
import inspect
import asyncio
import logging
from typing import List, Dict, Any, Optional, Tuple
import httpx
from pydantic import BaseModel, Field
from nasio.core.config import CONFIG_PATH, get_app_config
from nasio.services.task_engine import task_engine

logger = logging.getLogger("nasio.chat")

DATA_DIR = os.path.dirname(CONFIG_PATH)
CHAT_SESSIONS_FILE = os.path.join(DATA_DIR, "chat_sessions.json")


class ToolCallTrace(BaseModel):
    tool_name: str
    arguments: Dict[str, Any] = Field(default_factory=dict)
    result_preview: str = ""
    status: str = "SUCCESS"  # SUCCESS, ERROR
    duration_ms: int = 0


class ChatMessageModel(BaseModel):
    id: str = Field(default_factory=lambda: f"msg_{uuid.uuid4().hex[:10]}")
    role: str  # user, assistant
    content: str
    tool_calls: List[ToolCallTrace] = Field(default_factory=list)
    mode: str = "llm"  # llm, local_fallback
    created_at: float = Field(default_factory=time.time)


class ChatSessionModel(BaseModel):
    session_id: str
    title: str
    messages: List[ChatMessageModel] = Field(default_factory=list)
    created_at: float = Field(default_factory=time.time)
    updated_at: float = Field(default_factory=time.time)


class ChatService:
    """
    服务端统一托管 AI 对话与 Agent Loop 引擎：
    1. 自动桥接 Nasio 注册的全部 MCP Tools 为大模型 Function Calling 工具；
    2. 在 NAS 服务端本地完成 [LLM 推理 -> 工具调用 -> 结果回传 -> 最终总结] 闭环，客户端断网或锁屏不中断；
    3. 当尚未配置外部大模型 API Key 时，提供本地智能快捷指令兜底引擎（Local Command Fallback），开箱即用。
    """

    _instance: Optional["ChatService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._sessions: Dict[str, ChatSessionModel] = {}
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(CHAT_SESSIONS_FILE):
                with open(CHAT_SESSIONS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        sess = ChatSessionModel(**item)
                        self._sessions[sess.session_id] = sess
        except Exception as e:
            logger.warning("Failed to load chat sessions from %s: %s", CHAT_SESSIONS_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            sess_list = [s.model_dump() for s in self._sessions.values()]
            sess_list = sorted(sess_list, key=lambda x: x["updated_at"], reverse=True)[:50]
            with open(CHAT_SESSIONS_FILE, "w", encoding="utf-8") as f:
                json.dump(sess_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save chat sessions to %s: %s", CHAT_SESSIONS_FILE, e)

    def _broadcast_ws(self, event: str, data: Dict[str, Any]):
        try:
            loop = asyncio.get_running_loop()
            if loop.is_running():
                asyncio.create_task(task_engine._broadcast({"event": event, "data": data}))
        except RuntimeError:
            pass

    def list_sessions(self) -> List[Dict[str, Any]]:
        sessions = sorted(self._sessions.values(), key=lambda x: x.updated_at, reverse=True)
        return [
            {
                "session_id": s.session_id,
                "title": s.title,
                "message_count": len(s.messages),
                "last_message": s.messages[-1].content[:80] if s.messages else "",
                "created_at": s.created_at,
                "updated_at": s.updated_at,
            }
            for s in sessions
        ]

    def get_session(self, session_id: str) -> Optional[ChatSessionModel]:
        return self._sessions.get(session_id)

    def create_session(self, title: str = "新对话") -> ChatSessionModel:
        sid = f"chat_{time.strftime('%Y%m%d')}_{uuid.uuid4().hex[:6]}"
        sess = ChatSessionModel(
            session_id=sid,
            title=title,
            messages=[],
            created_at=time.time(),
            updated_at=time.time(),
        )
        self._sessions[sid] = sess
        self._save_to_disk()
        return sess

    def delete_session(self, session_id: str) -> bool:
        if session_id in self._sessions:
            del self._sessions[session_id]
            self._save_to_disk()
            return True
        return False

    def _get_openai_tools_schema(self) -> List[Dict[str, Any]]:
        """从 FastMCP 动态提取全部注册工具并转换为 OpenAI Function Calling Schema"""
        from nasio.mcp.server import mcp

        openai_tools = []
        for t in mcp._tool_manager.list_tools():
            params = dict(t.parameters) if t.parameters else {"type": "object", "properties": {}}
            openai_tools.append({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": (t.description or "").strip()[:800],
                    "parameters": params,
                },
            })
        return openai_tools

    async def _execute_mcp_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Tuple[str, str, int]:
        from nasio.mcp.server import mcp

        start_ts = time.time()
        tool = mcp._tool_manager.get_tool(tool_name)
        if not tool:
            return json.dumps({"error": f"Tool '{tool_name}' not found"}, ensure_ascii=False), "ERROR", 0

        try:
            if inspect.iscoroutinefunction(tool.fn):
                res = await tool.fn(**arguments)
            else:
                res = await asyncio.to_thread(tool.fn, **arguments)
            dur = int((time.time() - start_ts) * 1000)
            res_str = res if isinstance(res, str) else json.dumps(res, ensure_ascii=False)
            status = "ERROR" if '"error":' in res_str[:120] else "SUCCESS"
            return res_str, status, dur
        except Exception as e:
            dur = int((time.time() - start_ts) * 1000)
            return json.dumps({"error": str(e)}, ensure_ascii=False), "ERROR", dur

    async def send_message(
        self,
        content: str,
        session_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        content = content.strip()
        if not content:
            raise ValueError("Message content cannot be empty")

        if not session_id or session_id not in self._sessions:
            title = content[:22] + ("..." if len(content) > 22 else "")
            sess = self.create_session(title=title)
        else:
            sess = self._sessions[session_id]
            if sess.title == "新对话" and len(sess.messages) == 0:
                sess.title = content[:22] + ("..." if len(content) > 22 else "")

        user_msg = ChatMessageModel(role="user", content=content)
        sess.messages.append(user_msg)
        sess.updated_at = time.time()
        self._save_to_disk()

        cfg = get_app_config()
        llm_cfg = cfg.llm

        # 判断是否已启用并配置了有效模型（Ollama 允许无 API Key）
        is_llm_ready = llm_cfg.enabled and bool(llm_cfg.base_url.strip()) and (
            bool(llm_cfg.api_key.strip()) or llm_cfg.provider.lower() == "ollama"
        )

        if is_llm_ready:
            assistant_msg = await self._run_llm_agent_loop(sess, content)
        else:
            assistant_msg = await self._run_local_intent_fallback(sess, content)

        sess.messages.append(assistant_msg)
        sess.updated_at = time.time()
        self._save_to_disk()

        return {
            "session_id": sess.session_id,
            "session_title": sess.title,
            "user_message": user_msg.model_dump(),
            "assistant_message": assistant_msg.model_dump(),
        }

    async def _run_llm_agent_loop(self, sess: ChatSessionModel, user_content: str) -> ChatMessageModel:
        cfg = get_app_config()
        llm_cfg = cfg.llm

        sys_prompt = (
            f"{llm_cfg.system_prompt}\n\n"
            f"当前 NAS 允许操作的沙箱白名单路径: {cfg.storage.allowed_paths}\n"
            f"回收站目录: {cfg.trash.trash_dir}\n"
            "工作原则：\n"
            "1. 在查看大目录前，优先调用 `get_directory_digest` 或 `sample_directory_files` 以节省上下文；\n"
            "2. 在执行批量整理、重命名、扁平化或垃圾清理时，若用户未明确要求立即执行，先用 `dry_run=True` 预览；\n"
            "3. 若用户要求直接执行高风险大批量操作，可调用 `request_user_approval` 或说明生成的 `transaction_id` 支持随时回滚。"
        )

        api_messages: List[Dict[str, Any]] = [{"role": "system", "content": sys_prompt}]
        # 注入最近 12 条上下文历史
        for m in sess.messages[-13:-1]:
            api_messages.append({"role": m.role, "content": m.content})
        api_messages.append({"role": "user", "content": user_content})

        tools_schema = self._get_openai_tools_schema()
        traces: List[ToolCallTrace] = []
        max_rounds = max(1, min(llm_cfg.max_tool_rounds, 15))

        base_url = llm_cfg.base_url.rstrip("/")
        if not base_url.endswith("/chat/completions"):
            endpoint = f"{base_url}/chat/completions"
        else:
            endpoint = base_url

        headers = {"Content-Type": "application/json"}
        if llm_cfg.api_key.strip():
            headers["Authorization"] = f"Bearer {llm_cfg.api_key.strip()}"

        try:
            async with httpx.AsyncClient(timeout=90.0) as client:
                for round_idx in range(max_rounds):
                    payload: Dict[str, Any] = {
                        "model": llm_cfg.model,
                        "messages": api_messages,
                        "temperature": llm_cfg.temperature,
                        "tools": tools_schema,
                    }

                    resp = await client.post(endpoint, json=payload, headers=headers)
                    if resp.status_code != 200:
                        err_text = resp.text[:400]
                        return ChatMessageModel(
                            role="assistant",
                            content=f"⚠️ 调用大模型接口返回异常 (HTTP {resp.status_code})：\n```\n{err_text}\n```\n请检查「设置 -> AI 大模型配置」中的 Base URL、API Key 与模型名称是否正确。",
                            tool_calls=traces,
                            mode="llm",
                        )

                    data = resp.json()
                    choice = (data.get("choices") or [{}])[0]
                    message = choice.get("message") or {}
                    tool_calls = message.get("tool_calls") or []

                    if not tool_calls:
                        final_text = message.get("content") or "操作已完成。"
                        return ChatMessageModel(
                            role="assistant",
                            content=final_text,
                            tool_calls=traces,
                            mode="llm",
                        )

                    # 追加 assistant 的 tool_calls 消息
                    api_messages.append(message)

                    for tc in tool_calls:
                        tc_id = tc.get("id") or f"call_{uuid.uuid4().hex[:8]}"
                        fn_obj = tc.get("function") or {}
                        fn_name = fn_obj.get("name", "")
                        raw_args = fn_obj.get("arguments") or "{}"
                        try:
                            parsed_args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
                        except Exception:
                            parsed_args = {}

                        self._broadcast_ws(
                            "CHAT_TOOL_RUNNING",
                            {
                                "session_id": sess.session_id,
                                "tool_name": fn_name,
                                "arguments": parsed_args,
                            },
                        )

                        res_str, status_str, dur_ms = await self._execute_mcp_tool(fn_name, parsed_args)
                        preview = res_str[:1200] + ("...(已截断)" if len(res_str) > 1200 else "")
                        traces.append(
                            ToolCallTrace(
                                tool_name=fn_name,
                                arguments=parsed_args,
                                result_preview=preview,
                                status=status_str,
                                duration_ms=dur_ms,
                            )
                        )

                        # 限制回传给大模型的单次工具输出长度，防止撑爆 Context
                        tool_output_for_llm = res_str[:6000] if len(res_str) > 6000 else res_str
                        api_messages.append({
                            "role": "tool",
                            "tool_call_id": tc_id,
                            "name": fn_name,
                            "content": tool_output_for_llm,
                        })

                return ChatMessageModel(
                    role="assistant",
                    content="已完成多步工具调用（达到单次最大推理轮次限制），请查看上方工具执行轨迹。",
                    tool_calls=traces,
                    mode="llm",
                )
        except Exception as e:
            logger.error("LLM agent loop error: %s", e)
            return ChatMessageModel(
                role="assistant",
                content=f"⚠️ 连接大模型服务失败：`{e}`\n请确认大模型网关地址可达，或在「设置」中检查 API 配置。",
                tool_calls=traces,
                mode="llm",
            )

    async def _run_local_intent_fallback(self, sess: ChatSessionModel, text: str) -> ChatMessageModel:
        """
        本地智能指令兜底引擎（当用户尚未配置外部大模型 API Key 时开箱即用）：
        自动识别目录摘要、垃圾扫描、剧集整理预览、存储状态、回收站与事务查询等高频意图并调用对应 MCP 工具。
        """
        cfg = get_app_config()
        allowed = cfg.storage.allowed_paths
        default_dl = allowed[0] if allowed else "/volume1/Download"
        default_media = allowed[1] if len(allowed) > 1 else default_dl

        # 尝试从用户输入中提取路径
        target_path = None
        for p in allowed:
            if p.lower() in text.lower():
                target_path = p
                break
        if not target_path:
            if "media" in text.lower() or "媒体" in text or "番" in text or "剧" in text:
                target_path = default_media
            else:
                target_path = default_dl

        traces: List[ToolCallTrace] = []
        lower_t = text.lower()

        if any(k in lower_t for k in ["摘要", "digest", "结构", "分析", "概览", "统计"]):
            args = {"dir_path": target_path, "max_depth": 4}
            res_str, st, dur = await self._execute_mcp_tool("get_directory_digest", args)
            traces.append(ToolCallTrace(tool_name="get_directory_digest", arguments=args, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            if "error" in data:
                reply = f"❌ 目录摘要扫描失败：`{data['error']}`"
            else:
                exts = ", ".join([f"`{e['extension']}` ({e['count']}个/{e['size_mb']}MB)" for e in data.get("extension_breakdown", [])[:6]])
                reply = (
                    f"### 📊 目录结构智能摘要：`{data.get('dir_path')}`\n"
                    f"- **文件总数**：`{data.get('total_files')}` 个 | **子目录数**：`{data.get('total_subdirs')}` 个\n"
                    f"- **总占用空间**：`{data.get('total_size_gb')} GB` (`{data.get('total_size_mb')} MB`)\n"
                    f"- **未完成下载文件**：`{data.get('incomplete_downloads_count')}` 个 | **疑似广告/垃圾文件**：`{data.get('suspected_rubbish_count')}` 个\n"
                    f"- **主要类型分布**：{exts or '无'}"
                )
        elif any(k in lower_t for k in ["垃圾", "广告", "rubbish", "clean", "清理"]):
            is_exec = "确认执行" in text or "立即清理" in text or "dry_run=false" in lower_t
            args = {"dir_path": target_path, "max_depth": 5, "dry_run": not is_exec}
            res_str, st, dur = await self._execute_mcp_tool("clean_resource_rubbish", args)
            traces.append(ToolCallTrace(tool_name="clean_resource_rubbish", arguments=args, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            if "error" in data:
                reply = f"❌ 垃圾广告扫描失败：`{data['error']}`"
            else:
                matched = data.get("total_matched", 0)
                tx_id = data.get("transaction_id")
                mode_label = "正式清理完成" if is_exec else "试运行预览 (Dry-Run)"
                reply = (
                    f"### 🧹 资源广告与垃圾清理 ({mode_label})\n"
                    f"- **目标目录**：`{data.get('dir_path')}`\n"
                    f"- **识别垃圾文件数**：`{matched}` 个\n"
                    + (f"- **已移入回收站**：`{data.get('cleaned_count')}` 个（事务 ID: `{tx_id}`，支持一键回滚）\n" if is_exec else "- 如需正式清理，可发送：**“立即清理下载目录中的垃圾文件”**\n")
                )
        elif any(k in lower_t for k in ["样本", "抽样", "sample", "命名"]):
            args = {"dir_path": target_path, "sample_per_group": 3}
            res_str, st, dur = await self._execute_mcp_tool("sample_directory_files", args)
            traces.append(ToolCallTrace(tool_name="sample_directory_files", arguments=args, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            reply = f"### 🔍 目录典型文件样本抽样 (`{target_path}`)\n共发现 `{data.get('total_groups', 0)}` 个文件分组，详情请展开上方工具调用卡片查阅。"
        elif any(k in lower_t for k in ["回滚", "事务", "撤销", "undo", "transaction"]):
            res_str, st, dur = await self._execute_mcp_tool("list_action_transactions", {"limit": 10})
            traces.append(ToolCallTrace(tool_name="list_action_transactions", arguments={"limit": 10}, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            txs = data.get("transactions", [])
            reply = f"### ⏪ 最近 AI 批量操作事务记录 (共 `{len(txs)}` 条)\n您可以在右上角「操作回滚」抽屉中点击任意一条事务执行一键原子恢复。"
        elif any(k in lower_t for k in ["回收站", "trash"]):
            res_str, st, dur = await self._execute_mcp_tool("list_trash_files", {"page": 1, "limit": 10})
            traces.append(ToolCallTrace(tool_name="list_trash_files", arguments={"page": 1, "limit": 10}, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            reply = f"### 🗑️ 回收站状态概览\n当前回收站共有 `{data.get('total', 0)}` 个软删除条目，支持随时原路还原。"
        else:
            res_str, st, dur = await self._execute_mcp_tool("get_system_status", {})
            traces.append(ToolCallTrace(tool_name="get_system_status", arguments={}, result_preview=res_str[:1000], status=st, duration_ms=dur))
            data = json.loads(res_str)
            pools = data.get("storage_pools", [])
            pool_lines = "\n".join([
                f"- `{p.get('path')}`：已用 `{p.get('used_gb', 0)} GB` / 总计 `{p.get('total_gb', 0)} GB` (`{p.get('used_percent', 0)}%`)"
                if p.get("exists") else f"- `{p.get('path')}`：未挂载"
                for p in pools
            ])
            reply = (
                f"### 🖥️ Nasio 系统与存储池状态\n"
                f"{pool_lines or '- 暂无存储池数据'}\n"
                f"- **当前活跃后台任务数**：`{data.get('active_tasks_count', 0)}`\n"
            )

        reply += (
            "\n\n---\n"
            "💡 *当前处于「本地快捷指令模式」。若需开启自由多轮自然语言推理与全自动工具编排，请前往「设置 -> AI 大模型配置」开启并配置 DeepSeek / OpenAI / Ollama 模型。*"
        )
        return ChatMessageModel(
            role="assistant",
            content=reply,
            tool_calls=traces,
            mode="local_fallback",
        )

    async def test_llm_connection(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        provider: Optional[str] = None,
    ) -> Dict[str, Any]:
        cfg = get_app_config().llm
        target_url = (base_url or cfg.base_url or "").strip().rstrip("/")
        target_key = cfg.api_key if (api_key is None or api_key == "******") else api_key.strip()
        target_model = (model or cfg.model or "").strip()
        target_provider = (provider or cfg.provider or "openai_compatible").strip().lower()

        if not target_url:
            return {"success": False, "error": "Base URL 不能为空"}
        if not target_model:
            return {"success": False, "error": "Model 名称不能为空"}
        if not target_key and target_provider != "ollama":
            return {"success": False, "error": "API Key 不能为空（非本地 Ollama 模式）"}

        endpoint = target_url if target_url.endswith("/chat/completions") else f"{target_url}/chat/completions"
        headers = {"Content-Type": "application/json"}
        if target_key:
            headers["Authorization"] = f"Bearer {target_key}"

        start_ts = time.time()
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                resp = await client.post(
                    endpoint,
                    headers=headers,
                    json={
                        "model": target_model,
                        "messages": [{"role": "user", "content": "请回复 OK"}],
                        "max_tokens": 16,
                    },
                )
                latency_ms = int((time.time() - start_ts) * 1000)
                if resp.status_code == 200:
                    data = resp.json()
                    reply = ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "OK")
                    return {
                        "success": True,
                        "latency_ms": latency_ms,
                        "model": target_model,
                        "reply": reply.strip()[:100],
                    }
                return {
                    "success": False,
                    "latency_ms": latency_ms,
                    "error": f"HTTP {resp.status_code}: {resp.text[:250]}",
                }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
            }


TupleResult = Any
chat_service = ChatService()
