import os
import json
import time
import logging
from typing import List, Optional, Union, Dict, Any
from mcp.server.fastmcp import FastMCP
from nasio.core.config import get_app_config
from nasio.services.config_service import ConfigService
from nasio.services.trash_service import TrashService
from nasio.services.downloader_service import DownloaderService
from nasio.services.file_service import FileGovernanceService
from nasio.services.task_engine import task_engine
from nasio.services.agent_task_service import agent_task_service
from nasio.services.missing_mcp_service import missing_mcp_service
from nasio.services.skill_service import skill_service
from nasio.services.rss_service import rss_service, RssFilterRule
from nasio.services.transaction_service import transaction_service
from nasio.services.approval_service import approval_service


logger = logging.getLogger("nasio.mcp")

# 创建 FastMCP 实例（启用 stateless_http 防止容器重启或连接空闲断开后客户端报 Session not found）
try:
    mcp = FastMCP("Nasio", stateless_http=True)
except TypeError:
    mcp = FastMCP("Nasio")


# ==========================================
# 1. 系统与配置类 Tools
# ==========================================

@mcp.tool()
def get_system_status() -> str:
    """获取绿联 NAS 允许访问存储池的磁盘可用空间、使用率及系统当前活跃任务数。"""
    pools = ConfigService.get_storage_pools_status()
    active_tasks = len([t for t in task_engine.list_tasks() if t.status == "RUNNING"])
    return json.dumps({"storage_pools": pools, "active_tasks_count": active_tasks}, ensure_ascii=False, indent=2)


@mcp.tool()
def get_mcp_config() -> str:
    """查看 Nasio 当前运行配置，包括允许操作的目录白名单（allowed_paths）、回收站路径及外部下载器接入状态。"""
    cfg = get_app_config()
    data = {
        "allowed_paths": cfg.storage.allowed_paths,
        "max_search_depth": cfg.storage.max_search_depth,
        "trash_dir": cfg.trash.trash_dir,
        "trash_retention_days": cfg.trash.retention_days,
        "qbittorrent_enabled": cfg.downloaders.qbittorrent.enabled,
        "aria2_enabled": cfg.downloaders.aria2.enabled,
        "default_engine": cfg.downloaders.default_engine,
    }
    return json.dumps(data, ensure_ascii=False, indent=2)


@mcp.tool()
def test_downloader_connection(downloader_type: str = "qbittorrent") -> str:
    """
    测试 NAS 外部下载器连通性与健康状态。
    :param downloader_type: 下载器类型，可选 'qbittorrent' 或 'aria2'。
    """
    result = DownloaderService.test_downloader_connection(downloader_type)
    return json.dumps(result, ensure_ascii=False, indent=2)


# ==========================================
# 2. 异步长任务管理类 Tools
# ==========================================

@mcp.tool()
def get_task_status(task_id: str) -> str:
    """
    依据 task_id 查询后台耗时任务（大文件下载、解压缩、重复文件扫描等）的实时执行进度、速度及结果。
    :param task_id: 任务编号。
    """
    task = task_engine.get_task(task_id)
    if not task:
        return json.dumps({"error": f"Task '{task_id}' not found"}, ensure_ascii=False)
    return json.dumps(task.model_dump(), ensure_ascii=False, indent=2)


@mcp.tool()
def cancel_task(task_id: str) -> str:
    """
    中断并取消正在执行中的后台任务。
    :param task_id: 任务编号。
    """
    success = task_engine.cancel_task(task_id)
    return json.dumps({"task_id": task_id, "cancelled": success}, ensure_ascii=False)


# ==========================================
# 3. 混合下载引擎 Tools
# ==========================================

@mcp.tool()
def create_download_task(
    url: str,
    save_dir: str,
    filename: Optional[str] = None,
    engine_override: str = "auto",
    extract_audio_only: bool = False,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    统一创建下载任务。系统根据 URL 协议与参数智能路由：
    - http/https 直链：内置分块多线程断点续传；
    - 网页流媒体视频（B站、YouTube等）：内置 yt-dlp 抓取最高画质或提取音频；
    - magnet 磁力链与 .torrent：自动转推至 NAS 已配置的 qBittorrent 或 aria2。
    该方法为异步执行，立即返回 task_id。
    :param url: 下载目标链接。
    :param save_dir: 保存目录（必须位于白名单内）。
    :param filename: 指定保存文件名（可选）。
    :param engine_override: 强制指定引擎（auto / builtin / yt-dlp / qbittorrent / aria2）。
    :param extract_audio_only: 针对视频流是否仅提取为 MP3 音频。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填；若准备批量下载，强烈建议先调用 start_agent_task 并在每次调用时传入其返回的 ID，以便大屏聚合呈现）。
    """
    try:
        # 后端自动兜底：未携带 agent_task_id 时自动注册托管长任务（共2步：派发与底层执行完成）
        if not agent_task_id:
            target_name = filename or os.path.basename(url.split("?")[0]) or url[:30]
            task = agent_task_service.start_task(
                title=f"离线下载: {target_name}",
                description=f"[自动托管] URL: {url}",
                total_steps=2,
            )
            agent_task_id = task.agent_task_id
            agent_task_service.report_step(
                agent_task_id,
                step_name="派发下载任务",
                status="RUNNING",
                progress=10.0,
            )

        res = DownloaderService.dispatch_download(
            url=url,
            save_dir=save_dir,
            filename=filename,
            engine_override=engine_override,
            extract_audio_only=extract_audio_only,
            agent_task_id=agent_task_id,
        )
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if agent_task_id:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 4. 文件检索与元数据 Tools
# ==========================================

@mcp.tool()
def search_files(
    root_path: str,
    name_pattern: Optional[str] = None,
    extensions: Optional[List[str]] = None,
    min_size_mb: Optional[float] = None,
    max_size_mb: Optional[float] = None,
    modified_after: Optional[str] = None,
    max_depth: int = 5,
    limit: int = 50,
) -> str:
    """
    在指定目录下多条件实时检索文件。
    :param root_path: 检索根目录（必须在白名单内）。
    :param name_pattern: 通配符或正则匹配（例如 '*.mkv' 或 'S01E.*'）。
    :param extensions: 后缀筛选列表（例如 ['mp4', 'mkv']）。
    :param min_size_mb: 最小文件大小 (MB)。
    :param max_size_mb: 最大文件大小 (MB)。
    :param modified_after: 修改时间下限 (ISO 格式如 '2026-01-01T00:00:00')。
    :param max_depth: 最大递归深度。
    :param limit: 最大返回数量（默认 50）。
    """
    try:
        res = FileGovernanceService.search_files(
            root_path=root_path,
            name_pattern=name_pattern,
            extensions=extensions,
            min_size_mb=min_size_mb,
            max_size_mb=max_size_mb,
            modified_after=modified_after,
            max_depth=max_depth,
            limit=limit,
        )
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def get_file_metadata(file_path: str) -> str:
    """
    深度提取文件的结构化元数据：
    - 视频：分辨率、时长、视频编码、音轨声道、内嵌字幕；
    - 音频：时长、码率、歌手、专辑、曲名；
    - 图片：分辨率、格式、相机 EXIF 拍摄参数；
    - 文档：前 1000 字符文本预览。
    :param file_path: 目标文件路径。
    """
    try:
        res = FileGovernanceService.get_file_metadata(file_path)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def list_directory_tree(dir_path: str, depth: int = 2) -> str:
    """
    以轻量树状结构概览目标目录的层级结构。
    :param dir_path: 目录路径。
    :param depth: 展开深度（默认 2）。
    """
    try:
        res = FileGovernanceService.list_directory_tree(dir_path, depth)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def get_directory_digest(dir_path: str, max_depth: int = 4) -> str:
    """
    [Token 极省推荐] 获取目标目录的结构指纹与智能统计摘要。
    不返回冗长的文件名列表，仅用极低 Token 返回：文件总数、子目录总数、总大小、按后缀名的体积/数量分布、一级子目录占用排行、未完成下载数及疑似广告垃圾文件数。
    建议在浏览大型目录或规划整理方案前优先调用此工具。
    :param dir_path: 目标目录路径（必须在白名单内）。
    :param max_depth: 最大统计递归深度（默认 4）。
    """
    try:
        res = FileGovernanceService.get_directory_digest(dir_path, max_depth=max_depth)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def sample_directory_files(dir_path: str, sample_per_group: int = 3, max_depth: int = 3) -> str:
    """
    [Token 极省推荐] 典型文件样本嗅探工具。
    按 (子目录, 扩展名) 分组，每组仅抽样返回几个代表性文件名及该组文件总数，帮助 AI 快速学习字幕组/剧集命名规律并编写正则表达式，避免全量列出成百上千个文件撑爆上下文。
    :param dir_path: 目标目录路径。
    :param sample_per_group: 每个分组抽样的代表性文件名数量（默认 3）。
    :param max_depth: 最大递归深度（默认 3）。
    """
    try:
        res = FileGovernanceService.sample_directory_files(
            dir_path=dir_path,
            sample_per_group=sample_per_group,
            max_depth=max_depth,
        )
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)



# ==========================================
# 5. 文件整理与批量处理 Tools
# ==========================================

@mcp.tool()
def batch_organize_files(
    source_dir: str,
    target_dir: str,
    strategy: str = "by_extension",
    pattern: Optional[str] = None,
    conflict_resolution: str = "rename_suffix",
    dry_run: bool = True,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    批量规整文件到目标目录。
    :param source_dir: 待整理的源文件夹。
    :param target_dir: 整理后的目标目录。
    :param strategy: 策略规则（by_extension: 按类型分 Videos/Images 等; by_date: 按 YYYY/MM 归档; by_pattern: 正则命名捕获组建目录）。
    :param pattern: 当 strategy='by_pattern' 时的正则。
    :param conflict_resolution: 冲突处理（skip / rename_suffix / overwrite）。
    :param dry_run: 是否为试运行模式（强烈建议首次传入 True 预览方案，用户确认后再执行 False）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not dry_run and not agent_task_id:
        is_auto = True
        src_name = os.path.basename(source_dir.rstrip('/\\')) or source_dir
        task = agent_task_service.start_task(
            title=f"文件归档整理: {src_name}",
            description=f"[自动托管] {source_dir} -> {target_dir} ({strategy})",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行文件规整", status="RUNNING", progress=50.0)

    try:
        res = FileGovernanceService.batch_organize_files(
            source_dir=source_dir,
            target_dir=target_dir,
            strategy=strategy,
            pattern=pattern,
            conflict_resolution=conflict_resolution,
            dry_run=dry_run,
        )
        if agent_task_id and not dry_run:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="FILE_ORGANIZE",
                    action_id=f"org_{int(time.time())}",
                    summary=f"整理 {source_dir} -> {target_dir} ({strategy})",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="文件归档整理完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def batch_rename_files(
    directory: str,
    search_regex: str,
    replace_template: str,
    dry_run: bool = True,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    批量正则重命名文件。
    :param directory: 工作目录。
    :param search_regex: 匹配原文件名的正则表达式。
    :param replace_template: 替换模板。
    :param dry_run: 是否试运行（建议首次设为 True）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not dry_run and not agent_task_id:
        is_auto = True
        dir_name = os.path.basename(directory.rstrip('/\\')) or directory
        task = agent_task_service.start_task(
            title=f"批量重命名: {dir_name}",
            description=f"[自动托管] 目录: {directory}, 正则: {search_regex}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行批量重命名", status="RUNNING", progress=50.0)

    try:
        res = FileGovernanceService.batch_rename_files(
            directory=directory,
            search_regex=search_regex,
            replace_template=replace_template,
            dry_run=dry_run,
        )
        if agent_task_id and not dry_run:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="FILE_RENAME",
                    action_id=f"rename_{int(time.time())}",
                    summary=f"批量重命名: {directory} ({search_regex} -> {replace_template})",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="批量重命名完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def flatten_directory(
    source_dir: str,
    target_dir: Optional[str] = None,
    remove_empty_dirs: bool = True,
    dedup_companions: bool = True,
    conflict_resolution: str = "rename_suffix",
    extensions: Optional[List[str]] = None,
    max_depth: int = 5,
    dry_run: bool = True,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    一键将多级单集子目录中的多媒体文件（视频、音频、字幕）向上提取扁平化至目标目录，并支持自动去重伴随文件（如 Fonts.7z）及软删除空目录。
    :param source_dir: 待扁平化提取的源文件夹路径。
    :param target_dir: 提取后的目标父目录（选填，未传或与 source_dir 一致时执行原地向上扁平化提取）。
    :param remove_empty_dirs: 是否软删除已完全清空的子目录（移动至回收站，默认 True）。
    :param dedup_companions: 是否自动去重伴随文件（如 Fonts.7z、Fonts 字体目录等，相同哈希移入回收站，不同哈希追加序号，默认 True）。
    :param conflict_resolution: 同名文件冲突处理策略（rename_suffix / skip / overwrite，默认 rename_suffix）。
    :param extensions: 提取的文件扩展名白名单（选填，默认内置视频、音频、字幕及伴随资源白名单）。
    :param max_depth: 最大向下递归深度（默认 5）。
    :param dry_run: 是否为试运行模式（建议首次为 True 查看操作预览，确认无误后再传 False 执行）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not dry_run and not agent_task_id:
        is_auto = True
        src_name = os.path.basename(source_dir.rstrip('/\\')) or source_dir
        task = agent_task_service.start_task(
            title=f"目录扁平化提取: {src_name}",
            description=f"[自动托管] 源: {source_dir}, 目标: {target_dir or '原地提升'}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行目录扁平化提取", status="RUNNING", progress=50.0)

    try:
        res = FileGovernanceService.flatten_directory(
            source_dir=source_dir,
            target_dir=target_dir,
            remove_empty_dirs=remove_empty_dirs,
            dedup_companions=dedup_companions,
            conflict_resolution=conflict_resolution,
            extensions=extensions,
            max_depth=max_depth,
            dry_run=dry_run,
        )
        if agent_task_id and not dry_run:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="DIRECTORY_FLATTEN",
                    action_id=f"flat_{int(time.time())}",
                    summary=f"扁平化提取: {source_dir} -> {target_dir or '原地'} (移动: {res.get('total_moved')}, 去重: {res.get('total_deduped')}, 清理目录: {res.get('total_dirs_removed')})",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="目录扁平化提取完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def organize_series_seasons(
    root_dir: str,
    target_dir: Optional[str] = None,
    season_folder_template: str = "S{season}",
    scan_quarter_subdirs: bool = True,
    flatten_episode_subdirs: bool = True,
    remove_empty_dirs: bool = True,
    conflict_resolution: str = "rename_suffix",
    dry_run: bool = True,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    智能识别并归档多季动漫/剧集目录：扫描目标根目录（如 /volume1/Media/Comic）下的剧集文件夹，
    自动识别剧集基础名称与季度编号（如 第1季/第2季/S1/S2/Season 1 等），将相同剧集的不同季统一归并至
    '剧集名/S1/具体的剧集文件'、'剧集名/S2/具体的剧集文件' 标准层级，同时支持提取单集子目录媒体文件、去重伴随字体包及软删除原空目录。
    :param root_dir: 待整理的剧集根目录（如 '/volume1/Media/Comic'）。
    :param target_dir: 整理后的目标根目录（选填，默认与 root_dir 一致）。
    :param season_folder_template: 季目录命名模板（默认 'S{season}'，即 S1, S2）。
    :param scan_quarter_subdirs: 是否穿透识别如 '2026.7月新番' 等季度分类子目录并将剧集统一提取归并（默认 True）。
    :param flatten_episode_subdirs: 是否自动将单集子文件夹内的视频与字幕扁平化提升至 S1/S2 目录下（默认 True）。
    :param remove_empty_dirs: 是否将迁移后已清空的原剧集/季度目录软删除至回收站（默认 True）。
    :param conflict_resolution: 同名文件冲突处理策略（rename_suffix / skip / overwrite，默认 rename_suffix）。
    :param dry_run: 是否为试运行模式（建议首次为 True 查看预览方案，确认后再传 False 执行）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not dry_run and not agent_task_id:
        is_auto = True
        src_name = os.path.basename(root_dir.rstrip('/\\')) or root_dir
        task = agent_task_service.start_task(
            title=f"剧集多季归档整理: {src_name}",
            description=f"[自动托管] 根目录: {root_dir} -> 格式: 剧集名/{season_folder_template}/剧集文件",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行多季剧集目录统一归并", status="RUNNING", progress=50.0)

    try:
        res = FileGovernanceService.organize_series_seasons(
            root_dir=root_dir,
            target_dir=target_dir,
            season_folder_template=season_folder_template,
            scan_quarter_subdirs=scan_quarter_subdirs,
            flatten_episode_subdirs=flatten_episode_subdirs,
            remove_empty_dirs=remove_empty_dirs,
            conflict_resolution=conflict_resolution,
            dry_run=dry_run,
        )
        if agent_task_id and not dry_run:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="SERIES_SEASON_ORGANIZE",
                    action_id=f"series_{int(time.time())}",
                    summary=f"多季剧集归档: {root_dir} (共规整 {res.get('total_series_count')} 部剧集, 移动 {res.get('total_files_moved')} 个文件)",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="多季剧集目录归档完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def find_duplicate_files(scan_dir: str, min_size_mb: float = 1.0, agent_task_id: Optional[str] = None) -> str:
    """
    三级漏斗哈希全盘快速查重（按大小 -> 首尾哈希 -> 全量哈希）。
    该任务为异步执行，立即返回 task_id，可通过 get_task_status 查看查重结果。
    :param scan_dir: 扫描根目录。
    :param min_size_mb: 最小文件过滤阈值 (MB)。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    try:
        # 后端自动兜底：未携带 agent_task_id 时自动注册托管长任务
        if not agent_task_id:
            scan_name = os.path.basename(scan_dir.rstrip('/\\')) or scan_dir
            task = agent_task_service.start_task(
                title=f"全盘查重扫描: {scan_name}",
                description=f"[自动托管] 目录: {scan_dir}, 阈值: {min_size_mb}MB",
                total_steps=2,
            )
            agent_task_id = task.agent_task_id
            agent_task_service.report_step(
                agent_task_id,
                step_name="启动查重扫描",
                status="RUNNING",
                progress=10.0,
            )

        res = FileGovernanceService.find_duplicate_files(scan_dir, min_size_mb, agent_task_id=agent_task_id)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if agent_task_id:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def extract_archive(
    archive_path: str,
    dest_dir: Optional[str] = None,
    password: Optional[str] = None,
    remove_after_extract: bool = False,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    解压压缩包（支持 zip/rar/7z/tar，自动修复 Windows zip 中文文件名编码）。异步执行返回 task_id。
    :param archive_path: 压缩包路径。
    :param dest_dir: 解压输出目录（默认在原包同名文件夹下）。
    :param password: 解压密码（选填）。
    :param remove_after_extract: 解压成功后是否移入回收站。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    try:
        # 后端自动兜底：未携带 agent_task_id 时自动注册托管长任务
        if not agent_task_id:
            task = agent_task_service.start_task(
                title=f"解压文件: {os.path.basename(archive_path)}",
                description=f"[自动托管] 输出: {dest_dir or '同名目录'}",
                total_steps=2,
            )
            agent_task_id = task.agent_task_id
            agent_task_service.report_step(
                agent_task_id,
                step_name="启动解压缩",
                status="RUNNING",
                progress=10.0,
            )

        res = FileGovernanceService.extract_archive(
            archive_path=archive_path,
            dest_dir=dest_dir,
            password=password,
            remove_after_extract=remove_after_extract,
            agent_task_id=agent_task_id,
        )
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if agent_task_id:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def clean_resource_rubbish(
    dir_path: str,
    max_depth: int = 5,
    dry_run: bool = True,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    领域级高阶复合清理工具：自动扫描并安全软删除 BT/PT/压缩包解压目录中的发布站广告、网页链接 (.url/.html)、假快捷方式 (.lnk)、推广图文及系统冗余缓存 (.DS_Store/Thumbs.db)。
    正式清理（dry_run=False）时会将垃圾文件安全移入回收站并自动生成可一键回滚的 transaction_id。
    :param dir_path: 待扫描清理的目标目录路径。
    :param max_depth: 最大向下递归深度（默认 5）。
    :param dry_run: 是否为试运行预览模式（建议首次传 True 确认列表，再传 False 执行清理）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not dry_run and not agent_task_id:
        is_auto = True
        dir_name = os.path.basename(dir_path.rstrip("/\\")) or dir_path
        task = agent_task_service.start_task(
            title=f"资源垃圾广告清理: {dir_name}",
            description=f"[自动托管] 扫描清理目录: {dir_path}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行广告与垃圾文件清理", status="RUNNING", progress=50.0)

    try:
        res = FileGovernanceService.clean_resource_rubbish(
            dir_path=dir_path,
            max_depth=max_depth,
            dry_run=dry_run,
        )
        if agent_task_id and not dry_run:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="CLEAN_RUBBISH",
                    action_id=res.get("transaction_id") or f"clean_{int(time.time())}",
                    summary=f"清理广告与垃圾文件: {dir_path} (共清理 {res.get('cleaned_count')} 个文件)",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="垃圾广告清理完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 6. 回收站与防灾安全 Tools
# ==========================================

@mcp.tool()
def safe_delete_files(paths: List[str], reason: str = "", agent_task_id: Optional[str] = None) -> str:
    """
    安全软删除：将文件或文件夹移入 NAS 回收站（.trash 分区），记录元数据与操作事务以便随时一键回滚恢复。
    :param paths: 待删除的文件或文件夹路径列表。
    :param reason: 删除原因。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not agent_task_id:
        is_auto = True
        summary_desc = f"{len(paths)} 个条目" if len(paths) > 1 else (os.path.basename(paths[0]) if paths else "0 个条目")
        task = agent_task_service.start_task(
            title=f"文件软删除: {summary_desc}",
            description=f"[自动托管] 原因: {reason or '移入回收站'}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行软删除", status="RUNNING", progress=50.0)

    try:
        res = TrashService.safe_delete(paths, reason)
        trash_ids = [r["trash_id"] for r in res if r.get("success") and r.get("trash_id")]
        tx_id = None
        if trash_ids:
            try:
                tx = transaction_service.record_transaction(
                    operation_type="SAFE_DELETE",
                    summary=f"软删除 {len(trash_ids)} 个文件/目录 (原因: {reason or '无'})",
                    trash_ids=trash_ids,
                    agent_task_id=agent_task_id,
                )
                if tx:
                    tx_id = tx.transaction_id
            except Exception:
                pass

        action_summary = f"软删除 {len(paths)} 个文件/目录 (原因: {reason or '无'})"
        agent_task_service.add_sub_action(
            agent_task_id=agent_task_id,
            action_type="TRASH_DELETE",
            action_id=tx_id or f"del_{int(time.time())}",
            summary=action_summary,
            status="COMPLETED",
        )
        if is_auto:
            agent_task_service.report_step(agent_task_id, step_name="软删除完成", status="COMPLETED", progress=100.0)
            agent_task_service.complete_task(agent_task_id, result=res)
        return json.dumps({"items": res, "transaction_id": tx_id}, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def list_trash_files(keyword: Optional[str] = None, page: int = 1, limit: int = 20) -> str:
    """
    查看与检索回收站中已删除的文件列表及其原始路径、删除时间与大小。
    :param keyword: 模糊搜索关键字。
    :param page: 页码。
    :param limit: 每页条数。
    """
    try:
        res = TrashService.list_trash(keyword, page, limit)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def restore_trash_file(file_id: str, custom_target_dir: Optional[str] = None, agent_task_id: Optional[str] = None) -> str:
    """
    从回收站一键恢复文件至原路（若原目录不存在将自动重建）。
    :param file_id: 回收站元数据中的条目 ID。
    :param custom_target_dir: 自定义还原目标目录（可选）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not agent_task_id:
        is_auto = True
        task = agent_task_service.start_task(
            title=f"回收站还原: {file_id}",
            description=f"[自动托管] 目标: {custom_target_dir or '原路径'}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行文件还原", status="RUNNING", progress=50.0)

    try:
        res = TrashService.restore_file(file_id, custom_target_dir)
        agent_task_service.add_sub_action(
            agent_task_id=agent_task_id,
            action_type="TRASH_RESTORE",
            action_id=f"rst_{int(time.time())}",
            summary=f"还原回收站文件: {file_id}",
            status="COMPLETED",
        )
        if is_auto:
            agent_task_service.report_step(agent_task_id, step_name="文件还原完成", status="COMPLETED", progress=100.0)
            agent_task_service.complete_task(agent_task_id, result=res)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 7. AI Agent 复合长任务协作类 Tools
# ==========================================

@mcp.tool()
def start_agent_task(title: str, description: str = "", total_steps: int = 1) -> str:
    """
    【强烈推荐：批量或多步操作前置调用】
    当 AI Agent 准备执行多步复杂长任务或批量下发操作（例如：批量下发多个离线下载、多目录文件归档与重命名、全盘体检多步流）时，
    强烈建议优先调用此工具初始化长任务，并获取一个唯一的 agent_task_id。
    后续的所有批量子操作工具（如 create_download_task, safe_delete_files 等）均在参数中携带该 ID，并在关键里程碑调用 report_agent_task_step 汇报进度。
    这样前端监控大屏会将它们聚合呈现在同一个长任务时间轴内，而不是分散生成一堆独立的零碎单步任务。
    :param title: 任务简明主题（例如："新番批量下载与归档"）。
    :param description: 任务背景或目标描述。
    :param total_steps: 预估总步骤数（若执行 N 次批量下载，可传入 N+1 或 N）。
    """
    try:
        task = agent_task_service.start_task(title=title, description=description, total_steps=total_steps)
        return json.dumps(task.model_dump(), ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def report_agent_task_step(
    agent_task_id: str,
    step_name: str,
    step_index: Optional[int] = None,
    progress: Optional[float] = None,
    log_message: str = "",
    status: str = "COMPLETED",
) -> str:
    """
    在 AI Agent 执行长任务的不同阶段中汇报关键里程碑或操作日志，实时同步到 Web 控制台时间轴中。
    :param agent_task_id: start_agent_task 返回的长任务 ID。
    :param step_name: 当前步骤名称（例如："完成种子资源检索，共匹配到 12 话"）。
    :param step_index: 步骤序号（可选，默认自动递增）。
    :param progress: 任务整体百分比进度（0-100，可选）。
    :param log_message: 详细的日志或说明。
    :param status: 该步骤状态，可选 COMPLETED / RUNNING / FAILED。
    """
    try:
        task = agent_task_service.report_step(
            agent_task_id=agent_task_id,
            step_name=step_name,
            step_index=step_index,
            progress=progress,
            log_message=log_message,
            status=status,
        )
        if not task:
            return json.dumps({"error": f"Agent task '{agent_task_id}' not found"}, ensure_ascii=False)
        return json.dumps(task.model_dump(), ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def complete_agent_task(
    agent_task_id: str,
    summary: Optional[str] = None,
    prompt_template: Optional[str] = None,
) -> str:
    """
    标志 AI Agent 复合长任务全部顺利完成，并在 Web 端呈现成功归档状态。
    :param agent_task_id: 长任务 ID。
    :param summary: 最终执行总结或生成的结果概要。
    :param prompt_template: 智能体提炼的本任务标准化复现提示词（Prompt Template），包含任务上下文、目标与必要参数，便于用户直接复制发送给下一个智能体执行复现。
    """
    try:
        task = agent_task_service.complete_task(
            agent_task_id=agent_task_id,
            result={"summary": summary},
            prompt_template=prompt_template,
        )
        if not task:
            return json.dumps({"error": f"Agent task '{agent_task_id}' not found"}, ensure_ascii=False)
        return json.dumps(task.model_dump(), ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def report_missing_mcp_tool(
    tool_name: str,
    description: str,
    suggested_parameters: Optional[str] = None,
    scenario: Optional[str] = None,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    当智能体执行或完成任务过程中，发现缺少能够支撑底层业务执行的 MCP 工具或接口时，调用此工具向服务端上报能力诉求，供管理员与开发者在客户端面板查阅并扩展实现。
    :param tool_name: 期望/建议缺失的工具名称（例如 'extract_archive_with_password', 'video_transcode'）。
    :param description: 工具核心功能诉求与预期行为说明。
    :param suggested_parameters: 建议的入参描述或 JSON 示例字符串。
    :param scenario: 该工具缺失时的实际业务场景说明。
    :param agent_task_id: 当前正在执行的长任务 ID（若在任务中发现）。
    """
    try:
        model = missing_mcp_service.report_missing_tool(
            tool_name=tool_name,
            description=description,
            suggested_parameters=suggested_parameters,
            scenario=scenario,
            agent_task_id=agent_task_id,
        )
        return json.dumps({
            "status": "success",
            "message": f"缺失 MCP 工具 '{tool_name}' 已成功上报给服务端记录",
            "report_id": model.id,
            "created_at": model.created_at,
        }, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def fail_agent_task(agent_task_id: str, error_message: str) -> str:
    """
    当复合长任务遭遇不可逆异常或用户取消时，标记长任务失败并记录原因。
    :param agent_task_id: 长任务 ID。
    :param error_message: 失败原因说明。
    """
    try:
        task = agent_task_service.fail_task(agent_task_id=agent_task_id, error_message=error_message)
        if not task:
            return json.dumps({"error": f"Agent task '{agent_task_id}' not found"}, ensure_ascii=False)
        return json.dumps(task.model_dump(), ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 8. 智能体技能中心 (Skills & Workflows) Tools
# ==========================================

@mcp.tool()
def list_skills() -> str:
    """
    列出 Nasio 服务端持久化注册的全部 AI Agent 技能（Skills）与工作流规范清单。
    返回包含技能标识名、适用场景概述、标签及最后更新时间。
    """
    try:
        skills = skill_service.list_skills()
        return json.dumps({"skills": skills, "count": len(skills)}, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def get_skill(name: str) -> str:
    """
    获取 Nasio 服务端指定技能（Skill）的完整 Markdown 指导规范与端到端操作 SOP 流程。
    :param name: 技能英文标识名（例如 'anime_nas_workflow'）。
    """
    try:
        skill = skill_service.get_skill(name)
        if not skill:
            return json.dumps({"error": f"Skill '{name}' not found on server"}, ensure_ascii=False)
        return json.dumps(skill, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def sync_skill(
    name: str,
    description: str,
    content: str,
    tags: Optional[List[str]] = None,
    version: Optional[str] = "1.0.0",
) -> str:
    """
    向 Nasio 服务端注册或更新一个 Agent 技能（Skill）。
    该技能将被持久化落盘在服务端 data/skills/<name>/SKILL.md（带有标准 Frontmatter 元数据），供所有智能体及跨端客户端共享与自举安装。
    :param name: 技能标识名（仅允许英文字母、数字、下划线与短横线，例如 'anime_nas_workflow'）。
    :param description: 技能触发场景与功能简要概述（例如：'当用户提出新番/季度动漫检索...时，采用...'）。
    :param content: 技能完整 Markdown 规范内容（包含操作步骤、SOP 流程与最佳实践）。
    :param tags: 技能分类标签列表（例如 ['动漫', '下载', '工作流']）。
    :param version: 技能版本号（默认 '1.0.0'）。
    """
    try:
        saved = skill_service.save_or_update_skill(
            name=name,
            description=description,
            content=content,
            tags=tags,
            version=version or "1.0.0",
        )
        return json.dumps({
            "status": "success",
            "message": f"技能 '{name}' 已成功持久化同步到服务端",
            "skill": {
                "name": saved["name"],
                "description": saved["description"],
                "tags": saved["tags"],
                "version": saved["version"],
                "updated_at": saved["updated_at"],
                "path": saved["path"],
            }
        }, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 8. RSS 自动订阅与规则过滤下载 Tools
# ==========================================

@mcp.tool()
async def preview_rss_feed(
    feed_url: str,
    filter_rules_json: Optional[Union[str, List[Dict[str, Any]], List[Any]]] = None,
    url_extract_rule_json: Optional[Union[str, Dict[str, Any]]] = None,
    subtitle_language: Optional[str] = None,
) -> str:
    """
    在线预览并测试 RSS / Atom 订阅源中的条目与过滤规则匹配结果。
    :param feed_url: RSS 源 URL 地址。
    :param filter_rules_json: 过滤规则列表或 JSON 字符串（支持 List 或 JSON 字符串，每项包含 tag(标签名), attribute(属性名可选), pattern(正则表达式), mode('INCLUDE'或'EXCLUDE')，亦支持直接传入纯正则或字幕标识）。
    :param url_extract_rule_json: 可选提取规则（支持 Dict 或 JSON 字符串），指定下载资源提取规则，例如 {"tag": "enclosure", "attribute": "url"}。
    :param subtitle_language: 可选字幕语言过滤快捷标识（例如 '简中' / 'CHS' / '繁中' / 'CHT' / '双语' / 'JPN'），将自动追加对应的包含匹配规则。
    """
    try:
        res = await rss_service.preview_feed(
            feed_url=feed_url,
            filter_rules=filter_rules_json,
            url_extract_rule=url_extract_rule_json,
            subtitle_language=subtitle_language,
        )
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
async def create_rss_task(
    feed_url: str,
    save_dir: str,
    title: Optional[str] = None,
    filter_rules_json: Optional[Union[str, List[Dict[str, Any]], List[Any]]] = None,
    url_extract_rule_json: Optional[Union[str, Dict[str, Any]]] = None,
    check_interval_minutes: int = 15,
    download_engine: str = "auto",
    selected_guids_json: Optional[Union[str, List[str], List[Any]]] = None,
    download_existing: bool = True,
    agent_task_id: Optional[str] = None,
    subtitle_language: Optional[str] = None,
) -> str:
    """
    创建持续监听的 RSS 订阅下载任务。
    当检测到 RSS 有更新且条目符合正则属性过滤规则时，自动调用下载引擎保存到指定目录。
    支持存量条目选摘下载（如传入 selected_guids_json 则仅下载所选条目，其余标记为已处理）。
    支持绑定 AI 智能体长任务大屏（传入 agent_task_id）。
    :param feed_url: RSS / Atom 订阅地址。
    :param save_dir: 资源保存目录（必须在沙箱白名单内，如 /volume1/Media/Anime）。
    :param title: 订阅任务名称（可选，缺省使用频道标题）。
    :param filter_rules_json: 过滤规则列表或 JSON 字符串（支持 List 或 JSON 字符串，例如 '[{"tag":"title","pattern":"1080p","mode":"INCLUDE"}]' 或直接传列表对象）。
    :param url_extract_rule_json: 自定义提取资源 URL 的规则（可选，支持 Dict 或 JSON 字符串）。
    :param check_interval_minutes: 定时轮询间隔分钟数（默认 15）。
    :param download_engine: 下载器引擎（auto / qbittorrent / aria2 / builtin，默认 auto）。
    :param selected_guids_json: 首次创建时指定选摘下载的 GUID 列表（可选，支持 List 或 JSON 字符串）。
    :param download_existing: 若未指定 selected_guids_json，是否全量下载存量符合规则的条目（默认 True）。
    :param agent_task_id: 关联的 AI Agent 任务编号（必须传入以在监控时间轴大屏形成可跳转卡片）。
    :param subtitle_language: 可选字幕语言过滤快捷标识（例如 '简中' / 'CHS' / '繁中' / 'CHT' / '双语' / 'JPN'），将自动生成包含规则。
    """
    try:
        sub = await rss_service.create_subscription(
            feed_url=feed_url,
            save_dir=save_dir,
            title=title,
            filter_rules=filter_rules_json,
            url_extract_rule=url_extract_rule_json,
            check_interval_minutes=check_interval_minutes,
            download_engine=download_engine,
            selected_guids=selected_guids_json,
            download_existing=download_existing,
            agent_task_id=agent_task_id,
            subtitle_language=subtitle_language,
        )
        return json.dumps({
            "status": "success",
            "message": f"RSS 订阅任务 '{sub.title}' 创建成功",
            "subscription": sub.model_dump(),
        }, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def list_rss_tasks() -> str:
    """获取 NAS 当前所有已配置的 RSS 订阅监听任务列表与状态。"""
    subs = rss_service.list_subscriptions()
    data = [s.model_dump() for s in subs]
    return json.dumps(data, ensure_ascii=False, indent=2)


@mcp.tool()
def get_rss_task_detail(rss_id: str) -> str:
    """
    依据 rss_id 获取指定 RSS 订阅任务的详细配置、正则属性过滤规则以及历史抓取下载记录。
    :param rss_id: RSS 任务编号（例如 'rss_1a2b3c4d'）。
    """
    sub = rss_service.get_subscription(rss_id)
    if not sub:
        return json.dumps({"error": f"RSS 订阅 '{rss_id}' 不存在"}, ensure_ascii=False)
    return json.dumps(sub.model_dump(), ensure_ascii=False, indent=2)


@mcp.tool()
async def manage_rss_task(rss_id: str, action: str) -> str:
    """
    管理或操作已有的 RSS 订阅任务。
    :param rss_id: RSS 任务编号。
    :param action: 操作指令，支持 'pause'(暂停轮询), 'resume'(恢复轮询), 'delete'(删除订阅), 'refresh_now'(立即检查并抓取)。
    """
    act = action.strip().lower()
    try:
        if act == "pause":
            sub = rss_service.update_subscription(rss_id=rss_id, enabled=False)
            return json.dumps({"status": "success", "rss_id": rss_id, "enabled": False}, ensure_ascii=False)
        elif act == "resume":
            sub = rss_service.update_subscription(rss_id=rss_id, enabled=True)
            return json.dumps({"status": "success", "rss_id": rss_id, "enabled": True}, ensure_ascii=False)
        elif act == "delete":
            deleted = rss_service.delete_subscription(rss_id=rss_id)
            return json.dumps({"status": "success", "rss_id": rss_id, "deleted": deleted}, ensure_ascii=False)
        elif act == "refresh_now":
            res = await rss_service.check_subscription(rss_id=rss_id)
            return json.dumps(res, ensure_ascii=False, indent=2)
        else:
            return json.dumps({"error": f"不支持的操作: {action}，可选值为 pause, resume, delete, refresh_now"}, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
async def get_rss_subscription_items(rss_id: str) -> str:
    """
    在线抓取并查询指定 RSS 订阅任务当前的全部最新资源列表，返回各条目的标题、下载链接、是否匹配过滤规则及是否已下载状态。
    :param rss_id: RSS 任务编号（例如 'rss_1a2b3c4d'）。
    """
    try:
        data = await rss_service.get_subscription_items(rss_id)
        return json.dumps(data, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
async def download_rss_subscription_items(rss_id: str, items_json: str) -> str:
    """
    从指定 RSS 订阅的资源列表中挑选条目并立即触发下载，同步记录到该订阅的下载历史与去重集合中。
    :param rss_id: RSS 任务编号。
    :param items_json: 待下载资源条目的 JSON 数组字符串，每项需包含 guid, title, download_url。
    """
    try:
        items = json.loads(items_json)
        if not isinstance(items, list):
            return json.dumps({"error": "items_json 必须是 JSON 列表"}, ensure_ascii=False)
        res = await rss_service.download_selected_items(rss_id, items)
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


# ==========================================
# 9. AI 操作事务回滚与人机协同审批 Tools
# ==========================================

@mcp.tool()
def list_action_transactions(limit: int = 20) -> str:
    """
    查看 AI 近期执行的批量文件变更事务列表（包含 transaction_id、操作类型、变更文件数、关联回收站条目及是否已回滚）。
    :param limit: 返回最近条数（默认 20）。
    """
    try:
        txs = transaction_service.list_transactions(limit=limit)
        data = [
            {
                "transaction_id": t.transaction_id,
                "operation_type": t.operation_type,
                "summary": t.summary,
                "status": t.status,
                "movements_count": len(t.movements),
                "trash_count": len(t.trash_ids),
                "created_at": t.created_at,
                "rolled_back_at": t.rolled_back_at,
            }
            for t in txs
        ]
        return json.dumps({"transactions": data, "count": len(data)}, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
def rollback_agent_action(transaction_id: str, agent_task_id: Optional[str] = None) -> str:
    """
    一键原子回滚（后悔药）：根据 transaction_id 将某次批量操作（批量整理、重命名、扁平化、多季归档、垃圾清理或软删除）
    涉及的所有文件移动逆向移回原位，并将关联软删除至回收站的文件原路还原。
    :param transaction_id: 操作事务编号（如 'tx_20260930_a1b2c3'）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    is_auto = False
    if not agent_task_id:
        is_auto = True
        task = agent_task_service.start_task(
            title=f"操作事务回滚: {transaction_id}",
            description=f"[自动托管] 逆向恢复事务 {transaction_id}",
            total_steps=2,
        )
        agent_task_id = task.agent_task_id
        agent_task_service.report_step(agent_task_id, step_name="执行原子级事务回滚", status="RUNNING", progress=50.0)

    try:
        res = transaction_service.rollback_transaction(transaction_id)
        if agent_task_id:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="TRANSACTION_ROLLBACK",
                    action_id=f"rb_{transaction_id}",
                    summary=f"回滚事务 {transaction_id}: 恢复移动 {res.get('restored_movements_count')} 项, 还原回收站 {res.get('restored_trash_count')} 项",
                    status="COMPLETED" if res.get("success") else "FAILED",
                )
                if is_auto:
                    agent_task_service.report_step(agent_task_id, step_name="事务回滚完成", status="COMPLETED", progress=100.0)
                    agent_task_service.complete_task(agent_task_id, result=res)
            except Exception:
                pass
        return json.dumps(res, ensure_ascii=False, indent=2)
    except Exception as e:
        if is_auto:
            try:
                agent_task_service.fail_task(agent_task_id, str(e))
            except Exception:
                pass
        return json.dumps({"error": str(e)}, ensure_ascii=False)


@mcp.tool()
async def request_user_approval(
    title: str,
    description: str = "",
    diff_preview: str = "",
    wait_for_decision: bool = True,
    timeout_seconds: int = 120,
    agent_task_id: Optional[str] = None,
) -> str:
    """
    高危操作人机协同审批 (Human-in-the-Loop)：
    当 AI 准备执行大规模删除、大范围目录重组或存在潜在风险的操作时，调用此工具向 Nasio 客户端推送一张审批确认卡片。
    :param title: 审批标题（例如：'申请批量清理 38 个过期缓存文件'）。
    :param description: 操作原因与风险说明。
    :param diff_preview: 拟变更的文件列表或前后对比摘要文本。
    :param wait_for_decision: 是否阻塞等待用户在客户端点击同意/拒绝（默认 True）。
    :param timeout_seconds: 最长等待秒数（默认 120 秒）。
    :param agent_task_id: 关联的 AI Agent 复合长任务 ID（选填）。
    """
    try:
        item = approval_service.create_approval(
            title=title,
            description=description,
            diff_preview=diff_preview,
            agent_task_id=agent_task_id,
        )
        if wait_for_decision:
            decided = await approval_service.wait_for_decision(item.approval_id, timeout_seconds=timeout_seconds)
            return json.dumps(decided.model_dump(), ensure_ascii=False, indent=2)
        return json.dumps(item.model_dump(), ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)



