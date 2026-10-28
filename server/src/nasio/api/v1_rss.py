from typing import Dict, Any, Optional, List, Union
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query
from nasio.core.security import verify_auth_token
from nasio.services.rss_service import (
    rss_service,
    RssFilterRule,
    RssSubscriptionModel,
)

router = APIRouter(prefix="/rss", tags=["RSS Subscriptions"])


class RssPreviewRequest(BaseModel):
    feed_url: str = Field(..., description="RSS / Atom 源地址")
    filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = Field(default=None, description="过滤规则列表或 JSON 字符串")
    url_extract_rule: Optional[Union[Dict[str, str], str]] = Field(default=None, description="自定义资源提取规则或 JSON 字符串")
    subtitle_language: Optional[str] = Field(None, description="字幕语言过滤（如简中/繁中/CHS/CHT）")


class CreateRssSubscriptionRequest(BaseModel):
    feed_url: str = Field(..., description="RSS / Atom 源地址")
    save_dir: str = Field(..., description="下载资源保存路径")
    title: Optional[str] = Field(None, description="订阅名称，默认读取频道标题")
    filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = Field(default=None, description="过滤规则列表或 JSON 字符串")
    url_extract_rule: Optional[Union[Dict[str, str], str]] = Field(default=None, description="自定义资源提取规则或 JSON 字符串")
    check_interval_minutes: int = Field(15, description="定时轮询间隔分钟数")
    download_engine: str = Field("auto", description="下载引擎: auto / qbittorrent / aria2 / builtin")
    selected_guids: Optional[Union[List[str], List[Any], str]] = Field(None, description="首次创建时选摘下载的 GUID 列表或 JSON 字符串")
    download_existing: bool = Field(True, description="若未传 selected_guids 时，是否全量下载存量条目")
    agent_task_id: Optional[str] = Field(None, description="关联的智能体任务 ID")
    subtitle_language: Optional[str] = Field(None, description="字幕语言过滤（如简中/繁中/CHS/CHT）")


class UpdateRssSubscriptionRequest(BaseModel):
    title: Optional[str] = None
    save_dir: Optional[str] = None
    filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = None
    url_extract_rule: Optional[Union[Dict[str, str], str]] = None
    check_interval_minutes: Optional[int] = None
    download_engine: Optional[str] = None
    enabled: Optional[bool] = None
    subtitle_language: Optional[str] = None


class RssItemDownloadRequest(BaseModel):
    guid: str
    title: str
    download_url: str
    link: Optional[str] = ""
    pub_date: Optional[str] = ""


class DownloadSelectedItemsRequest(BaseModel):
    items: List[RssItemDownloadRequest]


@router.post("/preview", dependencies=[Depends(verify_auth_token)])
async def preview_rss_feed(req: RssPreviewRequest) -> Dict[str, Any]:
    """在线解析并预览 RSS 源内容，测试正则规则的命中情况"""
    try:
        return await rss_service.preview_feed(
            feed_url=req.feed_url,
            filter_rules=req.filter_rules,
            url_extract_rule=req.url_extract_rule,
            subtitle_language=req.subtitle_language,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"解析 RSS 源失败: {str(e)}")


@router.get("", dependencies=[Depends(verify_auth_token)])
async def list_rss_subscriptions() -> List[Dict[str, Any]]:
    """获取所有已配置的 RSS 订阅列表"""
    subs = rss_service.list_subscriptions()
    return [s.model_dump() for s in subs]


@router.post("", dependencies=[Depends(verify_auth_token)])
async def create_rss_subscription(req: CreateRssSubscriptionRequest) -> Dict[str, Any]:
    """创建新的 RSS 订阅任务"""
    try:
        sub = await rss_service.create_subscription(
            feed_url=req.feed_url,
            save_dir=req.save_dir,
            title=req.title,
            filter_rules=req.filter_rules,
            url_extract_rule=req.url_extract_rule,
            check_interval_minutes=req.check_interval_minutes,
            download_engine=req.download_engine,
            selected_guids=req.selected_guids,
            download_existing=req.download_existing,
            agent_task_id=req.agent_task_id,
            subtitle_language=req.subtitle_language,
        )
        return sub.model_dump()
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{rss_id}", dependencies=[Depends(verify_auth_token)])
async def get_rss_subscription_detail(rss_id: str) -> Dict[str, Any]:
    """获取单个 RSS 订阅任务的详细配置及抓取下载历史记录"""
    sub = rss_service.get_subscription(rss_id)
    if not sub:
        raise HTTPException(status_code=404, detail=f"RSS 订阅 '{rss_id}' 不存在")
    return sub.model_dump()


@router.put("/{rss_id}", dependencies=[Depends(verify_auth_token)])
async def update_rss_subscription(rss_id: str, req: UpdateRssSubscriptionRequest) -> Dict[str, Any]:
    """修改 RSS 订阅的属性、规则或轮询时间"""
    try:
        sub = rss_service.update_subscription(
            rss_id=rss_id,
            title=req.title,
            save_dir=req.save_dir,
            filter_rules=req.filter_rules,
            url_extract_rule=req.url_extract_rule,
            check_interval_minutes=req.check_interval_minutes,
            download_engine=req.download_engine,
            enabled=req.enabled,
            subtitle_language=req.subtitle_language,
        )
        return sub.model_dump()
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/{rss_id}", dependencies=[Depends(verify_auth_token)])
async def delete_rss_subscription(rss_id: str) -> Dict[str, Any]:
    """删除指定的 RSS 订阅任务"""
    success = rss_service.delete_subscription(rss_id)
    if not success:
        raise HTTPException(status_code=404, detail=f"RSS 订阅 '{rss_id}' 不存在")
    return {"rss_id": rss_id, "deleted": True}


@router.post("/{rss_id}/refresh", dependencies=[Depends(verify_auth_token)])
async def refresh_rss_subscription(rss_id: str) -> Dict[str, Any]:
    """立即强制触发一次 RSS 检查与增量资源下载"""
    try:
        return await rss_service.check_subscription(rss_id)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{rss_id}/toggle", dependencies=[Depends(verify_auth_token)])
async def toggle_rss_subscription(rss_id: str) -> Dict[str, Any]:
    """切换 RSS 订阅启用/暂停状态"""
    try:
        enabled = rss_service.toggle_subscription(rss_id)
        return {"rss_id": rss_id, "enabled": enabled}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{rss_id}/items", dependencies=[Depends(verify_auth_token)])
async def get_rss_subscription_items(rss_id: str) -> Dict[str, Any]:
    """获取指定 RSS 订阅当前远端的全部资源列表，标注过滤规则命中与下载状态"""
    try:
        return await rss_service.get_subscription_items(rss_id)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"获取 RSS 资源列表失败: {str(e)}")


@router.post("/{rss_id}/download", dependencies=[Depends(verify_auth_token)])
async def download_selected_rss_items(rss_id: str, req: DownloadSelectedItemsRequest) -> Dict[str, Any]:
    """手动选摘下载指定的 RSS 资源条目，派发至下载器并同步计入订阅历史"""
    try:
        return await rss_service.download_selected_items(
            rss_id=rss_id,
            items=[item.model_dump() for item in req.items],
        )
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"派发下载失败: {str(e)}")
