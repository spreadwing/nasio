from typing import Dict, Any, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, Query
from nasio.core.security import verify_auth_token
from nasio.services.downloader_service import DownloaderService

router = APIRouter(prefix="/downloaders", tags=["Downloaders"])


class SetDownloaderConfigRequest(BaseModel):
    download_limit_kb: Optional[int] = Field(None, description="下载全局限速 (KB/s), 0 为不限速")
    upload_limit_kb: Optional[int] = Field(None, description="上传全局限速 (KB/s), 0 为不限速")
    default_save_path: Optional[str] = Field(None, description="默认保存路径")
    max_active_downloads: Optional[int] = Field(None, description="最大同时下载任务数 (0 或 -1 为不限)")
    max_active_torrents: Optional[int] = Field(None, description="最大总活动任务数 (0 或 -1 为不限)")
    default_category: Optional[str] = Field(None, description="默认任务分类标签")
    queueing_enabled: Optional[bool] = Field(None, description="是否启用任务排队调度")
    auto_stop_seeding: Optional[bool] = Field(None, description="下载完成时自动停止做种")


@router.post("/test", dependencies=[Depends(verify_auth_token)])
async def test_downloader_connection(
    downloader_type: str = Query("qbittorrent", description="qbittorrent or aria2")
) -> Dict[str, Any]:
    """测试下载器连通性与鉴权状态"""
    return DownloaderService.test_downloader_connection(downloader_type)


@router.get("/config", dependencies=[Depends(verify_auth_token)])
async def get_downloader_config() -> Dict[str, Any]:
    """获取下载器限速与全局路径配置"""
    return DownloaderService.get_downloader_config()


@router.post("/config", dependencies=[Depends(verify_auth_token)])
async def set_downloader_config(req: SetDownloaderConfigRequest) -> Dict[str, Any]:
    """设置下载器限速与全局路径"""
    return DownloaderService.set_downloader_config(
        download_limit_kb=req.download_limit_kb,
        upload_limit_kb=req.upload_limit_kb,
        default_save_path=req.default_save_path,
        max_active_downloads=req.max_active_downloads,
        max_active_torrents=req.max_active_torrents,
        default_category=req.default_category,
        queueing_enabled=req.queueing_enabled,
        auto_stop_seeding=req.auto_stop_seeding,
    )


@router.post("/torrents/{torrent_hash}/pause", dependencies=[Depends(verify_auth_token)])
async def pause_torrent(torrent_hash: str) -> Dict[str, Any]:
    """暂停指定 Torrent 任务"""
    success = DownloaderService.pause_torrent(torrent_hash)
    return {"torrent_hash": torrent_hash, "paused": success}


@router.post("/torrents/{torrent_hash}/resume", dependencies=[Depends(verify_auth_token)])
async def resume_torrent(torrent_hash: str) -> Dict[str, Any]:
    """恢复指定 Torrent 任务"""
    success = DownloaderService.resume_torrent(torrent_hash)
    return {"torrent_hash": torrent_hash, "resumed": success}


@router.post("/torrents/{torrent_hash}/recheck", dependencies=[Depends(verify_auth_token)])
async def recheck_torrent(torrent_hash: str) -> Dict[str, Any]:
    """重新校验指定 Torrent 任务"""
    success = DownloaderService.recheck_torrent(torrent_hash)
    return {"torrent_hash": torrent_hash, "rechecked": success}


@router.delete("/torrents/{torrent_hash}", dependencies=[Depends(verify_auth_token)])
async def delete_torrent(
    torrent_hash: str,
    delete_files: bool = Query(False, description="是否同时从磁盘删除下载的文件"),
) -> Dict[str, Any]:
    """删除指定 Torrent 任务，支持一并清除本地文件"""
    success = DownloaderService.delete_qbittorrent_torrent(torrent_hash, delete_files=delete_files)
    return {"torrent_hash": torrent_hash, "deleted": success, "delete_files": delete_files}

