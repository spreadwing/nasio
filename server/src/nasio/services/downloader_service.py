import os
import re
import time
import asyncio
import logging
from typing import Dict, Any, Optional, List
import httpx
from nasio.core.config import get_app_config
from nasio.core.security import validate_sandbox_path, ensure_nas_compatible_dir
from nasio.services.task_engine import task_engine, TaskType

logger = logging.getLogger("nasio.downloader")


class DownloaderService:
    @classmethod
    def get_qb_client(cls):
        cfg = get_app_config()
        qb_cfg = cfg.downloaders.qbittorrent
        if not qb_cfg.enabled and not qb_cfg.url:
            return None
        import qbittorrentapi
        client = qbittorrentapi.Client(
            host=qb_cfg.url,
            username=qb_cfg.username,
            password=qb_cfg.password,
            REQUESTS_ARGS={"timeout": (3, 5)},
        )
        client.auth_log_in()
        return client

    @classmethod
    def test_downloader_connection(cls, downloader_type: str = "qbittorrent") -> Dict[str, Any]:
        """测试外部下载器连通性与鉴权"""
        cfg = get_app_config()
        dtype = downloader_type.lower()

        if dtype == "qbittorrent":
            try:
                qbt_client = cls.get_qb_client()
                if not qbt_client:
                    return {"connected": False, "status": "error", "error": "qBittorrent is not configured or disabled"}
                version = qbt_client.app.version
                api_version = None
                try:
                    api_version = qbt_client.app.web_api_version
                except Exception:
                    pass
                all_torrents = qbt_client.torrents_info()
                active_torrents = len([t for t in all_torrents if t.get("state") in ["downloading", "uploading"]])
                return {
                    "connected": True,
                    "status": "ok",
                    "type": "qbittorrent",
                    "version": version,
                    "api_version": api_version,
                    "total_torrents": len(all_torrents),
                    "active_torrents": active_torrents,
                }
            except Exception as e:
                return {"connected": False, "status": "error", "type": "qbittorrent", "error": str(e)}

        elif dtype == "aria2":
            aria_cfg = cfg.downloaders.aria2
            if not aria_cfg.enabled and not aria_cfg.rpc_url:
                return {"connected": False, "status": "error", "error": "aria2 is not configured or disabled"}
            try:
                rpc_payload = {
                    "jsonrpc": "2.0",
                    "id": "nasio_test",
                    "method": "aria2.getVersion",
                    "params": [f"token:{aria_cfg.rpc_secret}"] if aria_cfg.rpc_secret else [],
                }
                with httpx.Client(timeout=5.0) as client:
                    resp = client.post(aria_cfg.rpc_url, json=rpc_payload)
                    res_json = resp.json()
                    if "result" in res_json:
                        return {
                            "connected": True,
                            "status": "ok",
                            "type": "aria2",
                            "version": res_json["result"].get("version"),
                        }
                    else:
                        return {"connected": False, "status": "error", "type": "aria2", "error": res_json.get("error")}
            except Exception as e:
                return {"connected": False, "status": "error", "type": "aria2", "error": str(e)}

        return {"connected": False, "status": "error", "error": f"Unsupported downloader type: {downloader_type}"}

    @classmethod
    def get_qbittorrent_torrents(cls, limit: int = 100) -> List[Dict[str, Any]]:
        """获取 qBittorrent 中的所有种子并转为统一字典格式"""
        try:
            client = cls.get_qb_client()
            if not client:
                return []
            torrents = client.torrents_info()
            result = []
            for t in torrents:
                state = t.get("state", "")
                if state in ["downloading", "forcedDL", "forceDL", "allocating", "metaDL", "stalledDL"]:
                    status = "RUNNING"
                elif state in ["pausedDL", "stoppedDL"]:
                    status = "PAUSED"
                elif state in ["queuedDL", "checkingDL", "checkingResumeData", "moving"]:
                    status = "PENDING"
                elif state in ["uploading", "stalledUP", "queuedUP", "forcedUP", "forceUP", "completed", "pausedUP", "stoppedUP", "checkingUP"]:
                    status = "COMPLETED"
                elif state in ["error", "missingFiles"]:
                    status = "FAILED"
                else:
                    status = "PENDING"

                dlspeed = t.get("dlspeed", 0)
                upspeed = t.get("upspeed", 0)
                speed_str = "0 B/s"
                if dlspeed > 0:
                    speed_str = f"↓ {round(dlspeed / (1024 * 1024), 2)} MB/s"
                elif upspeed > 0:
                    speed_str = f"↑ {round(upspeed / (1024 * 1024), 2)} MB/s"

                prog = round(float(t.get("progress", 0.0)) * 100, 2)
                if status == "COMPLETED" and prog < 100:
                    prog = 100.0

                eta = t.get("eta", 0)
                if eta >= 8640000 or eta < 0:
                    eta = 0

                torrent_dict = {
                    "task_id": f"qb_{t.get('hash', '')}",
                    "task_type": "DOWNLOAD",
                    "status": status,
                    "progress": prog,
                    "created_at": float(t.get("added_on", time.time())),
                    "updated_at": float(t.get("last_activity", time.time())),
                    "detail": {
                        "name": t.get("name"),
                        "hash": t.get("hash"),
                        "engine": "qbittorrent",
                        "state": state,
                        "category": t.get("category", ""),
                        "save_path": t.get("save_path", ""),
                        "total_bytes": t.get("total_size") or t.get("size") or 0,
                        "downloaded_bytes": t.get("downloaded") or 0,
                        "speed": speed_str,
                        "eta_seconds": eta,
                        "num_seeds": t.get("num_seeds", 0),
                        "num_leechs": t.get("num_leechs", 0),
                    },
                    "error": f"qBittorrent: {state}" if status == "FAILED" else None,
                    "result": None,
                }
                result.append(torrent_dict)
            return result[:limit]
        except Exception as e:
            logger.warning("Failed to fetch qBittorrent torrents: %s", e)
            return []

    @classmethod
    def delete_qbittorrent_torrent(cls, torrent_hash: str, delete_files: bool = False) -> bool:
        """删除 qBittorrent 中的任务"""
        try:
            client = cls.get_qb_client()
            if not client:
                return False
            client.torrents_delete(torrent_hashes=torrent_hash, delete_files=delete_files)
            return True
        except Exception as e:
            logger.error("Failed to delete qBittorrent torrent %s: %s", torrent_hash, e)
            return False

    @classmethod
    def pause_torrent(cls, torrent_hash: str) -> bool:
        """暂停 qBittorrent 中的任务"""
        try:
            client = cls.get_qb_client()
            if not client:
                return False
            client.torrents_pause(torrent_hashes=torrent_hash)
            return True
        except Exception as e:
            logger.error("Failed to pause torrent %s: %s", torrent_hash, e)
            return False

    @classmethod
    def resume_torrent(cls, torrent_hash: str) -> bool:
        """恢复/继续 qBittorrent 中的任务"""
        try:
            client = cls.get_qb_client()
            if not client:
                return False
            client.torrents_resume(torrent_hashes=torrent_hash)
            return True
        except Exception as e:
            logger.error("Failed to resume torrent %s: %s", torrent_hash, e)
            return False

    @classmethod
    def recheck_torrent(cls, torrent_hash: str) -> bool:
        """重新校验 qBittorrent 中的任务"""
        try:
            client = cls.get_qb_client()
            if not client:
                return False
            client.torrents_recheck(torrent_hashes=torrent_hash)
            return True
        except Exception as e:
            logger.error("Failed to recheck torrent %s: %s", torrent_hash, e)
            return False

    @classmethod
    def get_downloader_config(cls) -> Dict[str, Any]:
        """获取外部下载器限速与全局路径配置"""
        cfg = get_app_config()
        result = {
            "default_engine": cfg.downloaders.default_engine,
            "allowed_paths": cfg.storage.allowed_paths,
            "qbittorrent": {
                "enabled": cfg.downloaders.qbittorrent.enabled,
                "url": cfg.downloaders.qbittorrent.url,
                "default_category": cfg.downloaders.qbittorrent.default_category,
                "download_limit_kb": 0,
                "upload_limit_kb": 0,
                "default_save_path": "/volume1/Download",
                "max_active_downloads": 5,
                "max_active_torrents": 10,
                "queueing_enabled": True,
                "auto_stop_seeding": cfg.downloaders.qbittorrent.auto_stop_seeding,
            },
        }
        try:
            client = cls.get_qb_client()
            if client:
                dl_limit = client.transfer_download_limit()
                up_limit = client.transfer_upload_limit()
                prefs = client.app_preferences()
                result["qbittorrent"]["download_limit_kb"] = int(dl_limit // 1024) if dl_limit else 0
                result["qbittorrent"]["upload_limit_kb"] = int(up_limit // 1024) if up_limit else 0
                result["qbittorrent"]["default_save_path"] = prefs.get("save_path", "/volume1/Download")
                result["qbittorrent"]["max_active_downloads"] = prefs.get("max_active_downloads", 5)
                result["qbittorrent"]["max_active_torrents"] = prefs.get("max_active_torrents", 10)
                result["qbittorrent"]["queueing_enabled"] = prefs.get("queueing_enabled", True)
                result["qbittorrent"]["default_category"] = cfg.downloaders.qbittorrent.default_category
                result["qbittorrent"]["auto_stop_seeding"] = cfg.downloaders.qbittorrent.auto_stop_seeding
        except Exception as e:
            logger.debug("Failed to read qb runtime config: %s", e)
        return result

    @classmethod
    def set_downloader_config(
        cls,
        download_limit_kb: Optional[int] = None,
        upload_limit_kb: Optional[int] = None,
        default_save_path: Optional[str] = None,
        max_active_downloads: Optional[int] = None,
        max_active_torrents: Optional[int] = None,
        default_category: Optional[str] = None,
        queueing_enabled: Optional[bool] = None,
        auto_stop_seeding: Optional[bool] = None,
    ) -> Dict[str, Any]:
        """设置外部下载器限速、并发队列、全局路径与停种策略"""
        try:
            client = cls.get_qb_client()
            if not client:
                return {"success": False, "error": "qBittorrent client not available"}
            if download_limit_kb is not None:
                limit_bytes = int(download_limit_kb * 1024) if download_limit_kb > 0 else 0
                client.transfer_set_download_limit(limit=limit_bytes)
            if upload_limit_kb is not None:
                limit_bytes = int(upload_limit_kb * 1024) if upload_limit_kb > 0 else 0
                client.transfer_set_upload_limit(limit=limit_bytes)

            qb_prefs = {}
            if default_save_path:
                valid_path = validate_sandbox_path(default_save_path)
                qb_prefs["save_path"] = valid_path
            if max_active_downloads is not None:
                qb_prefs["max_active_downloads"] = 999 if max_active_downloads <= 0 else max_active_downloads
            if max_active_torrents is not None:
                qb_prefs["max_active_torrents"] = 999 if max_active_torrents <= 0 else max_active_torrents
            if queueing_enabled is not None:
                qb_prefs["queueing_enabled"] = queueing_enabled
            if auto_stop_seeding is not None:
                cfg = get_app_config()
                cfg.downloaders.qbittorrent.auto_stop_seeding = auto_stop_seeding
                from nasio.core.config import ConfigManager
                ConfigManager().save(cfg)
                if auto_stop_seeding:
                    qb_prefs["max_ratio_enabled"] = True
                    qb_prefs["max_ratio"] = 0.0
                    qb_prefs["max_ratio_act"] = 0
                else:
                    qb_prefs["max_ratio_enabled"] = False
                    qb_prefs["max_ratio"] = -1.0
            if qb_prefs:
                client.app_set_preferences(prefs=qb_prefs)

            if default_category is not None:
                cat = default_category.strip()
                if cat:
                    cfg = get_app_config()
                    cfg.downloaders.qbittorrent.default_category = cat
                    from nasio.core.config import ConfigManager
                    ConfigManager().save(cfg)
                    try:
                        client.torrents_create_category(category=cat)
                    except Exception:
                        pass

            return {"success": True, "config": cls.get_downloader_config()}
        except Exception as e:
            logger.error("Failed to update downloader config: %s", e)
            return {"success": False, "error": str(e)}

    @classmethod
    def _is_magnet_or_torrent(cls, url: str) -> bool:
        return url.startswith("magnet:?") or url.endswith(".torrent")

    @classmethod
    def _is_media_stream_url(cls, url: str) -> bool:
        media_domains = ["bilibili.com", "b23.tv", "youtube.com", "youtu.be", "vimeo.com", "tiktok.com"]
        return any(domain in url.lower() for domain in media_domains)

    @classmethod
    def dispatch_download(
        cls,
        url: str,
        save_dir: str,
        filename: Optional[str] = None,
        engine_override: Optional[str] = "auto",
        extract_audio_only: bool = False,
        agent_task_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        统一创建下载任务并交由后台执行
        """
        valid_dir = validate_sandbox_path(save_dir)
        ensure_nas_compatible_dir(valid_dir)

        engine = (engine_override or "auto").lower()
        if engine == "auto":
            if cls._is_magnet_or_torrent(url):
                engine = "qbittorrent"
            elif cls._is_media_stream_url(url):
                engine = "yt-dlp"
            else:
                engine = "builtin"

        task = task_engine.create_task(
            task_type=TaskType.DOWNLOAD,
            detail={
                "url": url,
                "save_dir": valid_dir,
                "filename": filename,
                "engine": engine,
                "extract_audio": extract_audio_only,
                "agent_task_id": agent_task_id,
            },
        )

        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="DOWNLOAD",
                    action_id=task.task_id,
                    summary=f"创建下载: {url[:80]}",
                )
            except Exception as e:
                logger.debug("Failed to link sub action to agent task: %s", e)

        # 启动异步后台工作协程
        asyncio.create_task(
            cls._execute_download_job(task.task_id, url, valid_dir, filename, engine, extract_audio_only)
        )

        return {
            "task_id": task.task_id,
            "engine": engine,
            "status": "RUNNING",
            "message": f"Download task dispatched via engine: {engine}",
        }

    @classmethod
    async def _execute_download_job(
        cls,
        task_id: str,
        url: str,
        save_dir: str,
        filename: Optional[str],
        engine: str,
        extract_audio: bool,
    ):
        try:
            if engine == "qbittorrent":
                await cls._run_qbittorrent_download(task_id, url, save_dir)
            elif engine == "aria2":
                await cls._run_aria2_download(task_id, url, save_dir)
            elif engine == "yt-dlp":
                await asyncio.to_thread(cls._run_ytdlp_download, task_id, url, save_dir, filename, extract_audio)
            else:
                await cls._run_builtin_http_download(task_id, url, save_dir, filename)
        except Exception as e:
            logger.error("Download failed for task %s: %s", task_id, e)
            task_engine.fail_task(task_id, str(e))

    @classmethod
    async def _run_builtin_http_download(cls, task_id: str, url: str, save_dir: str, filename: Optional[str]):
        """内置 HTTP/HTTPS 流式多块下载"""
        async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
            async with client.stream("GET", url) as response:
                response.raise_for_status()
                total_size = int(response.headers.get("content-length", 0))

                if not filename:
                    # 尝试从 Content-Disposition 解析
                    cd = response.headers.get("content-disposition", "")
                    fname_match = re.findall(r'filename\*?=(?:UTF-8\'\')?["\']?([^"\';]+)["\']?', cd)
                    if fname_match:
                        filename = fname_match[0]
                    else:
                        filename = os.path.basename(url.split("?")[0]) or f"file_{int(time.time())}"

                output_path = os.path.join(save_dir, filename)
                downloaded = 0
                start_time = time.time()
                last_update = start_time

                with open(output_path, "wb") as f:
                    async for chunk in response.aiter_bytes(chunk_size=64 * 1024):
                        if task_engine.is_cancelled(task_id):
                            logger.info("Download task %s cancelled by user", task_id)
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        now = time.time()
                        if now - last_update >= 0.5:
                            duration = now - start_time
                            speed_bps = downloaded / duration if duration > 0 else 0
                            speed_str = f"{round(speed_bps / (1024 * 1024), 2)} MB/s"
                            progress = (downloaded / total_size * 100) if total_size > 0 else 0.0
                            eta_seconds = int((total_size - downloaded) / speed_bps) if total_size > downloaded and speed_bps > 0 else 0
                            task_engine.update_progress(
                                task_id,
                                progress,
                                {
                                    "downloaded_bytes": downloaded,
                                    "total_bytes": total_size,
                                    "speed": speed_str,
                                    "eta_seconds": eta_seconds,
                                    "saved_file": output_path,
                                },
                            )
                            last_update = now

        if task_engine.is_cancelled(task_id):
            if os.path.exists(output_path):
                os.remove(output_path)
            return

        task_engine.complete_task(task_id, {"saved_path": output_path, "size_bytes": downloaded})

    @classmethod
    def _run_ytdlp_download(cls, task_id: str, url: str, save_dir: str, filename: Optional[str], extract_audio: bool):
        """调用 yt-dlp Python API 进行视频/音频抓取"""
        import yt_dlp

        out_template = os.path.join(save_dir, filename if filename else "%(title)s.%(ext)s")

        def progress_hook(d):
            if task_engine.is_cancelled(task_id):
                raise InterruptedError("Cancelled by user")
            if d.get("status") == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                downloaded = d.get("downloaded_bytes") or 0
                speed = d.get("speed") or 0
                speed_str = f"{round(speed / (1024 * 1024), 2)} MB/s" if speed else "0 MB/s"
                progress = (downloaded / total * 100) if total > 0 else 0.0
                task_engine.update_progress(
                    task_id,
                    progress,
                    {"speed": speed_str, "eta_seconds": d.get("eta") or 0},
                )

        ydl_opts = {
            "outtmpl": out_template,
            "progress_hooks": [progress_hook],
            "quiet": True,
            "no_warnings": True,
        }

        if extract_audio:
            ydl_opts.update({
                "format": "bestaudio/best",
                "postprocessors": [{
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "192",
                }],
            })

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            title = info.get("title", "media")
            task_engine.complete_task(task_id, {"title": title, "url": url})

    @classmethod
    async def _run_qbittorrent_download(cls, task_id: str, url: str, save_dir: str):
        cfg = get_app_config()
        import qbittorrentapi
        qb_cfg = cfg.downloaders.qbittorrent
        client = qbittorrentapi.Client(
            host=qb_cfg.url, username=qb_cfg.username, password=qb_cfg.password
        )
        client.auth_log_in()
        add_kwargs = {"urls": url, "save_path": save_dir, "category": qb_cfg.default_category}
        if qb_cfg.auto_stop_seeding:
            add_kwargs["ratio_limit"] = 0.0
            add_kwargs["seeding_time_limit"] = 0
        client.torrents_add(**add_kwargs)
        task_engine.complete_task(task_id, {"message": "Torrent sent to qBittorrent successfully", "save_path": save_dir})

    @classmethod
    async def _run_aria2_download(cls, task_id: str, url: str, save_dir: str):
        cfg = get_app_config()
        aria_cfg = cfg.downloaders.aria2
        rpc_payload = {
            "jsonrpc": "2.0",
            "id": task_id,
            "method": "aria2.addUri",
            "params": [
                [f"token:{aria_cfg.rpc_secret}"] if aria_cfg.rpc_secret else [],
                [url],
                {"dir": save_dir},
            ],
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(aria_cfg.rpc_url, json=rpc_payload)
            res = resp.json()
            if "error" in res:
                task_engine.fail_task(task_id, str(res["error"]))
            else:
                task_engine.complete_task(task_id, {"gid": res.get("result"), "message": "Dispatched to aria2"})
