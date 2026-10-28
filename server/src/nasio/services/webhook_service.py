import time
import hmac
import json
import hashlib
import asyncio
import logging
from typing import Dict, Any, Optional
import httpx
from nasio.core.config import get_app_config

logger = logging.getLogger("nasio.webhook")


class WebhookService:
    """
    NAS 主动事件总线与 Webhook 广播服务：
    当发生下载完成、RSS 命中新番、高危审批请求或空间不足时，主动向外部 AI Agent (如 Dify / n8n / 自建智能体网关)
    推送包含结构化上下文与建议执行 Prompt 的事件通知，使 AI 从“被动工具”升级为“主动管家”。
    """

    @classmethod
    def emit_event(
        cls,
        event_type: str,
        summary: str,
        data: Dict[str, Any],
        suggested_prompt: Optional[str] = None,
    ) -> None:
        cfg = get_app_config().webhook
        if not cfg.enabled or not cfg.url.strip():
            return
        if cfg.events and event_type not in cfg.events:
            return

        try:
            loop = asyncio.get_running_loop()
            if loop.is_running():
                asyncio.create_task(
                    cls._send_webhook(
                        url=cfg.url.strip(),
                        secret=cfg.secret.strip(),
                        event_type=event_type,
                        summary=summary,
                        data=data,
                        suggested_prompt=suggested_prompt,
                    )
                )
        except RuntimeError:
            pass

    @classmethod
    async def _send_webhook(
        cls,
        url: str,
        secret: str,
        event_type: str,
        summary: str,
        data: Dict[str, Any],
        suggested_prompt: Optional[str] = None,
    ) -> Dict[str, Any]:
        payload = {
            "event": event_type,
            "timestamp": time.time(),
            "summary": summary,
            "suggested_agent_prompt": suggested_prompt or f"[Nasio 事件通知] {summary}。请检查相关目录或任务状态并执行后续处理。",
            "data": data,
        }
        body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = {
            "Content-Type": "application/json; charset=utf-8",
            "X-Nasio-Event": event_type,
        }
        if secret:
            sig = hmac.new(secret.encode("utf-8"), body_bytes, hashlib.sha256).hexdigest()
            headers["X-Nasio-Signature"] = f"sha256={sig}"

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, content=body_bytes, headers=headers)
                logger.info("Webhook [%s] sent to %s, status=%d", event_type, url, resp.status_code)
                return {
                    "success": 200 <= resp.status_code < 300,
                    "status_code": resp.status_code,
                    "response": resp.text[:300],
                }
        except Exception as e:
            logger.warning("Failed to send webhook [%s] to %s: %s", event_type, url, e)
            return {"success": False, "error": str(e)}

    @classmethod
    async def test_webhook(cls, url: Optional[str] = None, secret: Optional[str] = None) -> Dict[str, Any]:
        cfg = get_app_config().webhook
        target_url = (url or cfg.url or "").strip()
        target_secret = secret if secret is not None and secret != "******" else cfg.secret
        if not target_url:
            return {"success": False, "error": "Webhook URL 不能为空"}

        return await cls._send_webhook(
            url=target_url,
            secret=target_secret or "",
            event_type="WEBHOOK_TEST",
            summary="Nasio 主动事件总线连通性测试成功",
            data={"test": True, "service": "Nasio"},
            suggested_prompt="收到 Nasio 测试事件，请回复确认连接正常。",
        )


webhook_service = WebhookService()
