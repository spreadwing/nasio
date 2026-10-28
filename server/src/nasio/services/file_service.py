import os
import re
import time
import stat as stat_mod
import fnmatch
import hashlib
import shutil
import zipfile
import subprocess
import asyncio
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional, Tuple
from nasio.core.security import validate_sandbox_path, ensure_nas_compatible_dir, apply_nas_permissions
from nasio.services.task_engine import task_engine, TaskType
from nasio.services.trash_service import TrashService

logger = logging.getLogger("nasio.file_service")


class FileGovernanceService:
    @classmethod
    def _assert_dir_accessible(cls, raw_path: str, valid_dir: str) -> None:
        """
        校验目录存在且具备读取/穿透权限：
        直接调用 os.stat 以便在父目录无 +x 穿透权限时透出真实的 PermissionError，
        避免 os.path.isdir 捕获 OSError 后误报 NotADirectoryError。
        """
        try:
            st = os.stat(valid_dir)
        except PermissionError as e:
            raise PermissionError(f"Permission denied accessing directory '{raw_path}': {e}") from e
        except FileNotFoundError as e:
            raise NotADirectoryError(f"'{raw_path}' does not exist or is not a directory") from e
        if not stat_mod.S_ISDIR(st.st_mode):
            raise NotADirectoryError(f"'{raw_path}' is not a directory")

    @classmethod
    def search_files(
        cls,
        root_path: str,
        name_pattern: Optional[str] = None,
        extensions: Optional[List[str]] = None,
        min_size_mb: Optional[float] = None,
        max_size_mb: Optional[float] = None,
        modified_after: Optional[str] = None,
        max_depth: int = 5,
        limit: int = 50,
    ) -> Dict[str, Any]:
        """多维度实时文件检索"""
        valid_root = validate_sandbox_path(root_path)
        cls._assert_dir_accessible(root_path, valid_root)

        results = []
        ext_set = {e.lower().lstrip(".") for e in extensions} if extensions else None
        mod_after_ts = None
        if modified_after:
            try:
                mod_after_ts = datetime.fromisoformat(modified_after).timestamp()
            except Exception:
                pass

        root_depth = valid_root.rstrip(os.sep).count(os.sep)

        for current_root, dirs, files in os.walk(valid_root):
            curr_depth = current_root.count(os.sep) - root_depth
            if curr_depth >= max_depth:
                dirs.clear()  # 阻止继续向下递归

            for f in files:
                if len(results) >= limit:
                    break

                # 1. 后缀过滤
                if ext_set:
                    _, ext = os.path.splitext(f)
                    if ext.lower().lstrip(".") not in ext_set:
                        continue

                # 2. 名称模式匹配
                if name_pattern:
                    if not fnmatch.fnmatch(f, name_pattern) and not re.search(name_pattern, f, re.I):
                        continue

                file_path = os.path.join(current_root, f)
                try:
                    stat = os.stat(file_path)
                except OSError:
                    continue

                # 3. 大小过滤 (MB)
                size_mb = stat.st_size / (1024 * 1024)
                if min_size_mb is not None and size_mb < min_size_mb:
                    continue
                if max_size_mb is not None and size_mb > max_size_mb:
                    continue

                # 4. 修改时间过滤
                if mod_after_ts is not None and stat.st_mtime < mod_after_ts:
                    continue

                results.append({
                    "name": f,
                    "path": file_path,
                    "size_mb": round(size_mb, 2),
                    "size_bytes": stat.st_size,
                    "mtime": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "is_dir": False,
                })

            if len(results) >= limit:
                break

        return {"total_found": len(results), "items": results}

    @classmethod
    def get_file_metadata(cls, file_path: str) -> Dict[str, Any]:
        """提取文件的详细元数据（音视频编码/时长、图片EXIF、文本摘要）"""
        valid_path = validate_sandbox_path(file_path)
        if not os.path.isfile(valid_path):
            raise FileNotFoundError(f"File '{file_path}' not found")

        stat = os.stat(valid_path)
        base_info = {
            "path": valid_path,
            "filename": os.path.basename(valid_path),
            "size_mb": round(stat.st_size / (1024 * 1024), 2),
            "mtime": datetime.fromtimestamp(stat.st_mtime).isoformat(),
        }

        _, ext = os.path.splitext(valid_path)
        ext = ext.lower().lstrip(".")

        video_exts = {"mp4", "mkv", "avi", "mov", "wmv", "flv", "webm"}
        audio_exts = {"mp3", "flac", "wav", "aac", "m4a", "ogg"}
        image_exts = {"jpg", "jpeg", "png", "webp", "gif", "bmp"}
        text_exts = {"txt", "md", "json", "yaml", "yml", "xml", "csv", "log"}

        # 1. 视频元数据
        if ext in video_exts:
            base_info["category"] = "video"
            try:
                from pymediainfo import MediaInfo
                media_info = MediaInfo.parse(valid_path)
                tracks = []
                for track in media_info.tracks:
                    if track.track_type == "General":
                        base_info["duration_seconds"] = round(float(track.duration or 0) / 1000, 1)
                        base_info["overall_bit_rate"] = track.overall_bit_rate
                    elif track.track_type == "Video":
                        base_info["resolution"] = f"{track.width}x{track.height}"
                        base_info["video_codec"] = track.format
                        base_info["frame_rate"] = track.frame_rate
                    elif track.track_type == "Audio":
                        tracks.append(f"{track.format} ({track.channel_s or 2}ch, {track.language or 'unknown'})")
                    elif track.track_type == "Text":
                        base_info.setdefault("subtitles", []).append(track.language or track.format)
                if tracks:
                    base_info["audio_tracks"] = tracks
            except Exception as e:
                base_info["meta_parse_error"] = str(e)
            return base_info

        # 2. 音频元数据
        if ext in audio_exts:
            base_info["category"] = "audio"
            try:
                import mutagen
                audio = mutagen.File(valid_path)
                if audio is not None:
                    base_info["duration_seconds"] = round(getattr(audio.info, "length", 0), 1)
                    base_info["bitrate"] = getattr(audio.info, "bitrate", 0)
                    if hasattr(audio, "tags") and audio.tags:
                        base_info["title"] = str(audio.tags.get("TIT2", audio.tags.get("title", [""]))[0])
                        base_info["artist"] = str(audio.tags.get("TPE1", audio.tags.get("artist", [""]))[0])
                        base_info["album"] = str(audio.tags.get("TALB", audio.tags.get("album", [""]))[0])
            except Exception as e:
                base_info["meta_parse_error"] = str(e)
            return base_info

        # 3. 图片 EXIF
        if ext in image_exts:
            base_info["category"] = "image"
            try:
                from PIL import Image, ExifTags
                with Image.open(valid_path) as img:
                    base_info["resolution"] = f"{img.width}x{img.height}"
                    base_info["format"] = img.format
                    exif_data = img._getexif()
                    if exif_data:
                        exif = {}
                        for tag_id, val in exif_data.items():
                            tag_name = ExifTags.TAGS.get(tag_id, str(tag_id))
                            if isinstance(val, (str, int, float)):
                                exif[tag_name] = val
                        base_info["exif"] = {
                            "Model": exif.get("Model"),
                            "DateTime": exif.get("DateTime"),
                            "ExposureTime": str(exif.get("ExposureTime")),
                            "FNumber": exif.get("FNumber"),
                            "ISOSpeedRatings": exif.get("ISOSpeedRatings"),
                        }
            except Exception as e:
                base_info["meta_parse_error"] = str(e)
            return base_info

        # 4. 文本前缀预览
        if ext in text_exts:
            base_info["category"] = "document"
            try:
                with open(valid_path, "r", encoding="utf-8", errors="ignore") as f:
                    base_info["preview_text"] = f.read(1000)
            except Exception as e:
                base_info["meta_parse_error"] = str(e)
            return base_info

        base_info["category"] = "other"
        return base_info

    @classmethod
    def list_directory_tree(cls, dir_path: str, depth: int = 2) -> Dict[str, Any]:
        """生成层级目录树预览"""
        valid_dir = validate_sandbox_path(dir_path)
        cls._assert_dir_accessible(dir_path, valid_dir)

        def build_tree(current_dir: str, current_depth: int):
            node = {
                "name": os.path.basename(current_dir) or current_dir,
                "path": current_dir,
                "is_dir": True,
                "children": [],
            }
            if current_depth > depth:
                return node
            try:
                entries = sorted(os.scandir(current_dir), key=lambda e: (not e.is_dir(), e.name.lower()))
                for e in entries:
                    if e.name.startswith("."):
                        continue
                    if e.is_dir():
                        node["children"].append(build_tree(e.path, current_depth + 1))
                    else:
                        stat = e.stat()
                        node["children"].append({
                            "name": e.name,
                            "path": e.path,
                            "is_dir": False,
                            "size_mb": round(stat.st_size / (1024 * 1024), 2),
                        })
            except PermissionError as e:
                if current_depth == 1:
                    raise PermissionError(f"Permission denied scanning directory '{dir_path}': {e}") from e
                node["permission_denied"] = True
            return node

        return build_tree(valid_dir, 1)

    @classmethod
    def batch_organize_files(
        cls,
        source_dir: str,
        target_dir: str,
        strategy: str = "by_extension",
        pattern: Optional[str] = None,
        conflict_resolution: str = "rename_suffix",
        dry_run: bool = True,
    ) -> Dict[str, Any]:
        """批量规整文件（支持 by_extension, by_date, by_pattern，支持 dry_run）"""
        valid_src = validate_sandbox_path(source_dir)
        valid_dst = validate_sandbox_path(target_dir)

        cls._assert_dir_accessible(source_dir, valid_src)

        actions = []
        category_map = {
            "Videos": ["mp4", "mkv", "avi", "mov", "flv", "wmv", "ts", "rmvb"],
            "Images": ["jpg", "jpeg", "png", "webp", "gif", "raw", "bmp"],
            "Music": ["mp3", "flac", "wav", "m4a", "aac", "ape"],
            "Documents": ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md"],
            "Archives": ["zip", "rar", "7z", "tar", "gz", "iso"],
        }
        ext_to_cat = {}
        for cat, ext_list in category_map.items():
            for e in ext_list:
                ext_to_cat[e] = cat

        for f in os.listdir(valid_src):
            src_file = os.path.join(valid_src, f)
            if not os.path.isfile(src_file) or f.startswith("."):
                continue

            _, ext = os.path.splitext(f)
            clean_ext = ext.lower().lstrip(".")

            sub_folder = "Others"
            if strategy == "by_extension":
                sub_folder = ext_to_cat.get(clean_ext, "Others")
            elif strategy == "by_date":
                mtime = os.path.getmtime(src_file)
                sub_folder = datetime.fromtimestamp(mtime).strftime("%Y/%m")
            elif strategy == "by_pattern" and pattern:
                match = re.search(pattern, f)
                if match and match.groups():
                    sub_folder = match.group(1).strip()

            dest_folder = os.path.join(valid_dst, sub_folder)
            dest_file = os.path.join(dest_folder, f)

            if os.path.exists(dest_file):
                if conflict_resolution == "skip":
                    continue
                elif conflict_resolution == "rename_suffix":
                    base, ext = os.path.splitext(f)
                    dest_file = os.path.join(dest_folder, f"{base}_{int(time.time())}{ext}")

            actions.append({"source": src_file, "destination": dest_file, "action": "MOVE"})

        tx_id = None
        if not dry_run:
            for act in actions:
                ensure_nas_compatible_dir(os.path.dirname(act["destination"]), reference_path=valid_src)
                shutil.move(act["source"], act["destination"])
                apply_nas_permissions(act["destination"], reference_path=valid_src)
            if actions:
                try:
                    from nasio.services.transaction_service import transaction_service
                    tx = transaction_service.record_transaction(
                        operation_type="BATCH_ORGANIZE",
                        summary=f"批量整理 {valid_src} -> {valid_dst} ({strategy}, 共 {len(actions)} 个文件)",
                        movements=actions,
                    )
                    if tx:
                        tx_id = tx.transaction_id
                except Exception as e:
                    logger.warning("Failed to record batch_organize transaction: %s", e)

        res = {
            "dry_run": dry_run,
            "total_planned": len(actions),
            "planned_actions": actions,
        }
        if tx_id:
            res["transaction_id"] = tx_id
        return res

    @classmethod
    def batch_rename_files(
        cls,
        directory: str,
        search_regex: str,
        replace_template: str,
        dry_run: bool = True,
    ) -> Dict[str, Any]:
        """批量正则重命名文件"""
        valid_dir = validate_sandbox_path(directory)
        cls._assert_dir_accessible(directory, valid_dir)

        actions = []
        reg = re.compile(search_regex)

        for f in os.listdir(valid_dir):
            src_path = os.path.join(valid_dir, f)
            if not os.path.isfile(src_path):
                continue

            if reg.search(f):
                new_name = reg.sub(replace_template, f)
                if new_name != f:
                    dst_path = os.path.join(valid_dir, new_name)
                    actions.append({"source": src_path, "new_name": new_name, "destination": dst_path})

        tx_id = None
        if not dry_run:
            for act in actions:
                shutil.move(act["source"], act["destination"])
                apply_nas_permissions(act["destination"], reference_path=valid_dir)
            if actions:
                try:
                    from nasio.services.transaction_service import transaction_service
                    tx = transaction_service.record_transaction(
                        operation_type="BATCH_RENAME",
                        summary=f"批量重命名 {valid_dir} (共 {len(actions)} 个文件)",
                        movements=actions,
                    )
                    if tx:
                        tx_id = tx.transaction_id
                except Exception as e:
                    logger.warning("Failed to record batch_rename transaction: %s", e)

        res = {
            "dry_run": dry_run,
            "total_matched": len(actions),
            "actions": actions,
        }
        if tx_id:
            res["transaction_id"] = tx_id
        return res

    @classmethod
    def _compute_file_hash(cls, filepath: str) -> str:
        """快速计算文件哈希：<= 50MB 计算完整 MD5；> 50MB 读取首尾 4MB + 文件大小"""
        size = os.path.getsize(filepath)
        hasher = hashlib.md5()
        if size <= 50 * 1024 * 1024:
            with open(filepath, "rb") as f:
                while chunk := f.read(65536):
                    hasher.update(chunk)
        else:
            with open(filepath, "rb") as f:
                hasher.update(f.read(4 * 1024 * 1024))
                f.seek(max(0, size - 4 * 1024 * 1024))
                hasher.update(f.read(4 * 1024 * 1024))
            hasher.update(str(size).encode())
        return hasher.hexdigest()

    @classmethod
    def flatten_directory(
        cls,
        source_dir: str,
        target_dir: Optional[str] = None,
        remove_empty_dirs: bool = True,
        dedup_companions: bool = True,
        conflict_resolution: str = "rename_suffix",
        extensions: Optional[List[str]] = None,
        max_depth: int = 5,
        dry_run: bool = True,
        _record_tx: bool = True,
    ) -> Dict[str, Any]:
        """
        将多级单集子目录中的多媒体文件提取扁平化至目标目录，支持自动去重伴随文件（Fonts.7z等）与软删除空目录。
        """
        valid_src = validate_sandbox_path(source_dir)
        cls._assert_dir_accessible(source_dir, valid_src)

        if target_dir:
            valid_dst = validate_sandbox_path(target_dir)
        else:
            valid_dst = valid_src

        valid_src = os.path.abspath(valid_src)
        valid_dst = os.path.abspath(valid_dst)
        is_inplace = (valid_src == valid_dst)

        # 扩展名白名单定义
        video_exts = {"mp4", "mkv", "avi", "mov", "flv", "wmv", "ts", "rmvb", "webm"}
        audio_exts = {"mp3", "flac", "wav", "m4a", "aac", "ape", "ogg", "opus"}
        subtitle_exts = {"ass", "srt", "sup", "ssa", "sub", "vtt", "idx"}
        archive_exts = {"zip", "7z", "rar", "tar", "gz"}
        font_exts = {"ttf", "otf", "ttc", "woff", "woff2"}
        meta_exts = {"nfo", "txt", "jpg", "jpeg", "png", "webp"}
        companion_ext_all = archive_exts | font_exts | meta_exts

        junk_names = {".ds_store", "thumbs.db", "desktop.ini"}
        incomplete_exts = {"!qb", "part", "crdownload", "tmp"}

        if extensions:
            allowed_exts = {e.lower().lstrip(".") for e in extensions}
        else:
            allowed_exts = video_exts | audio_exts | subtitle_exts | companion_ext_all

        def is_companion_file(fname: str, ext: str) -> bool:
            lower_name = fname.lower()
            if ext in font_exts:
                return True
            if "font" in lower_name and ext in archive_exts:
                return True
            if ext in {"nfo", "txt"} and any(k in lower_name for k in ["sp", "info", "readme", "release", "torrent"]):
                return True
            if ext in {"jpg", "jpeg", "png", "webp"} and any(k in lower_name for k in ["cover", "poster", "folder"]):
                return True
            if ext in archive_exts:
                return True
            return False

        src_depth = valid_src.rstrip(os.sep).count(os.sep)

        # 扫描目标目录已有文件建立缓存（dry_run 模式下若目标目录尚不存在则无需创建）
        dst_existing_files: Dict[str, Dict[str, Any]] = {}
        if os.path.isdir(valid_dst):
            for root, _, files in os.walk(valid_dst):
                for f in files:
                    full_p = os.path.join(root, f)
                    rel_p = os.path.relpath(full_p, valid_dst)
                    dst_existing_files[rel_p] = {
                        "path": full_p,
                        "size": os.path.getsize(full_p),
                        "hash": None,
                    }

        scanned_dirs = []
        files_to_process = []
        dir_files_map: Dict[str, List[str]] = {}

        for root, dirs, files in os.walk(valid_src):
            curr_depth = root.count(os.sep) - src_depth
            if curr_depth > max_depth:
                dirs.clear()
                continue

            if not is_inplace and os.path.commonpath([valid_dst, root]) == valid_dst:
                dirs.clear()
                continue

            if root != valid_src:
                scanned_dirs.append(root)

            dir_files_map[root] = [os.path.join(root, f) for f in files]

            if is_inplace and root == valid_src:
                continue

            for f in files:
                files_to_process.append((root, f))

        moved_actions = []
        dedup_actions = []
        skipped_actions = []
        warnings = []
        handled_src_files = set()
        planned_dst: Dict[str, Dict[str, Any]] = {}

        def get_existing_or_planned_hash(rel_path: str) -> Optional[str]:
            if rel_path in planned_dst:
                return planned_dst[rel_path]["hash"]
            if rel_path in dst_existing_files:
                entry = dst_existing_files[rel_path]
                if entry["hash"] is None:
                    entry["hash"] = cls._compute_file_hash(entry["path"])
                return entry["hash"]
            return None

        def is_target_occupied(rel_path: str) -> bool:
            return (rel_path in planned_dst) or (rel_path in dst_existing_files)

        for dir_path, f in files_to_process:
            src_path = os.path.join(dir_path, f)
            lower_name = f.lower()

            if lower_name in junk_names or lower_name.startswith("._"):
                handled_src_files.add(src_path)
                continue

            _, raw_ext = os.path.splitext(f)
            ext = raw_ext.lower().lstrip(".")

            if ext in incomplete_exts:
                skipped_actions.append({"source": src_path, "reason": f"Incomplete download file (.{ext}) skipped"})
                continue

            if ext not in allowed_exts:
                warnings.append(f"File '{src_path}' skipped: extension '.{ext}' not in allowed list")
                continue

            is_in_fonts_dir = os.path.basename(dir_path).lower() == "fonts"
            is_font_file = ext in font_exts

            if is_in_fonts_dir and is_font_file:
                target_rel = os.path.join("Fonts", f)
            else:
                target_rel = f

            src_hash = cls._compute_file_hash(src_path)
            is_companion = is_companion_file(f, ext) or is_font_file

            if is_companion and dedup_companions:
                if is_target_occupied(target_rel):
                    target_hash = get_existing_or_planned_hash(target_rel)
                    if target_hash == src_hash:
                        dedup_actions.append({
                            "source": src_path,
                            "reason": f"Duplicate companion file (identical hash matches '{target_rel}')",
                            "action": "DEDUP_TRASH",
                        })
                        handled_src_files.add(src_path)
                        continue
                    else:
                        base_n, ext_n = os.path.splitext(f)
                        counter = 1
                        while True:
                            cand_name = f"{base_n}_{counter}{ext_n}"
                            cand_rel = os.path.join("Fonts", cand_name) if (is_in_fonts_dir and is_font_file) else cand_name
                            if not is_target_occupied(cand_rel):
                                target_rel = cand_rel
                                break
                            if get_existing_or_planned_hash(cand_rel) == src_hash:
                                dedup_actions.append({
                                    "source": src_path,
                                    "reason": f"Duplicate companion file (identical hash matches '{cand_rel}')",
                                    "action": "DEDUP_TRASH",
                                })
                                handled_src_files.add(src_path)
                                break
                            counter += 1
                        if src_path in handled_src_files:
                            continue

                dest_full = os.path.join(valid_dst, target_rel)
                planned_dst[target_rel] = {"source": src_path, "hash": src_hash}
                moved_actions.append({
                    "source": src_path,
                    "destination": dest_full,
                    "type": "companion",
                    "action": "MOVE",
                })
                handled_src_files.add(src_path)
                continue

            if is_target_occupied(target_rel):
                target_hash = get_existing_or_planned_hash(target_rel)
                if target_hash == src_hash:
                    dedup_actions.append({
                        "source": src_path,
                        "reason": f"Duplicate media file (identical hash matches '{target_rel}')",
                        "action": "DEDUP_TRASH",
                    })
                    handled_src_files.add(src_path)
                    continue

                if conflict_resolution == "skip":
                    skipped_actions.append({"source": src_path, "reason": f"File '{target_rel}' exists, skipped by policy"})
                    continue
                elif conflict_resolution == "overwrite":
                    dest_full = os.path.join(valid_dst, target_rel)
                    planned_dst[target_rel] = {"source": src_path, "hash": src_hash}
                    moved_actions.append({
                        "source": src_path,
                        "destination": dest_full,
                        "type": "media",
                        "action": "OVERWRITE",
                    })
                    handled_src_files.add(src_path)
                    continue
                else:  # rename_suffix
                    base_n, ext_n = os.path.splitext(f)
                    counter = 1
                    while True:
                        cand_name = f"{base_n}_{counter}{ext_n}"
                        cand_rel = cand_name
                        if not is_target_occupied(cand_rel):
                            target_rel = cand_rel
                            break
                        if get_existing_or_planned_hash(cand_rel) == src_hash:
                            dedup_actions.append({
                                "source": src_path,
                                "reason": f"Duplicate media file (identical hash matches '{cand_rel}')",
                                "action": "DEDUP_TRASH",
                            })
                            handled_src_files.add(src_path)
                            break
                        counter += 1
                    if src_path in handled_src_files:
                        continue

            dest_full = os.path.join(valid_dst, target_rel)
            planned_dst[target_rel] = {"source": src_path, "hash": src_hash}
            moved_actions.append({
                "source": src_path,
                "destination": dest_full,
                "type": "media",
                "action": "MOVE",
            })
            handled_src_files.add(src_path)

        scanned_dirs.sort(key=lambda d: d.count(os.sep), reverse=True)
        empty_dirs_to_remove = []

        for d in scanned_dirs:
            if not remove_empty_dirs:
                break

            all_files_in_dir = dir_files_map.get(d, [])
            unhandled = [fp for fp in all_files_in_dir if fp not in handled_src_files]

            if not unhandled:
                empty_dirs_to_remove.append(d)
            else:
                rel_d = os.path.relpath(d, valid_src)
                unhandled_names = [os.path.basename(fp) for fp in unhandled]
                warnings.append(f"Directory '{rel_d}' retained: contains unhandled file(s): {unhandled_names}")

        collected_trash_ids: List[str] = []
        tx_id = None
        if not dry_run:
            ensure_nas_compatible_dir(valid_dst, reference_path=valid_src)
            trash_paths = [act["source"] for act in dedup_actions if os.path.exists(act["source"])]
            if trash_paths:
                del_res = TrashService.safe_delete(trash_paths, reason="Duplicate companion/media during flatten_directory")
                collected_trash_ids.extend([r["trash_id"] for r in del_res if r.get("success") and r.get("trash_id")])

            for act in moved_actions:
                src_p = act["source"]
                dst_p = act["destination"]
                if os.path.exists(src_p):
                    ensure_nas_compatible_dir(os.path.dirname(dst_p), reference_path=valid_src)
                    if act["action"] == "OVERWRITE" and os.path.exists(dst_p):
                        os.remove(dst_p)
                    shutil.move(src_p, dst_p)
                    apply_nas_permissions(dst_p, reference_path=valid_src)

            for d in empty_dirs_to_remove:
                if os.path.isdir(d):
                    for junk in os.listdir(d):
                        junk_p = os.path.join(d, junk)
                        if os.path.isfile(junk_p) or os.path.islink(junk_p):
                            try:
                                os.remove(junk_p)
                            except OSError:
                                pass
                    try:
                        del_res = TrashService.safe_delete([d], reason="Empty directory after flatten_directory")
                        collected_trash_ids.extend([r["trash_id"] for r in del_res if r.get("success") and r.get("trash_id")])
                    except Exception as e:
                        logger.warning("Failed to soft delete empty directory %s: %s", d, e)

            if _record_tx and (moved_actions or collected_trash_ids):
                try:
                    from nasio.services.transaction_service import transaction_service
                    tx = transaction_service.record_transaction(
                        operation_type="FLATTEN_DIR",
                        summary=f"扁平化提取 {valid_src} -> {valid_dst} (移动 {len(moved_actions)} 个文件)",
                        movements=moved_actions,
                        trash_ids=collected_trash_ids,
                    )
                    if tx:
                        tx_id = tx.transaction_id
                except Exception as e:
                    logger.warning("Failed to record flatten_directory transaction: %s", e)

        res = {
            "dry_run": dry_run,
            "source_dir": valid_src,
            "target_dir": valid_dst,
            "total_moved": len(moved_actions),
            "total_deduped": len(dedup_actions),
            "total_dirs_removed": len(empty_dirs_to_remove),
            "total_skipped": len(skipped_actions),
            "moved_files": [
                {"source": act["source"], "destination": act["destination"], "type": act["type"]}
                for act in moved_actions
            ],
            "deduped_companions": [
                {"source": act["source"], "reason": act["reason"]}
                for act in dedup_actions
            ],
            "removed_empty_dirs": empty_dirs_to_remove,
            "skipped_files": skipped_actions,
            "warnings": warnings,
            "_trash_ids": collected_trash_ids,
        }
        if tx_id:
            res["transaction_id"] = tx_id
        return res

    @classmethod
    def find_duplicate_files(
        cls,
        scan_dir: str,
        min_size_mb: float = 1.0,
        agent_task_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """三级漏斗哈希极速查重 (通过异步长任务执行)"""
        valid_dir = validate_sandbox_path(scan_dir)

        task = task_engine.create_task(
            task_type=TaskType.DUPLICATE_SCAN,
            detail={"scan_dir": valid_dir, "min_size_mb": min_size_mb, "agent_task_id": agent_task_id},
        )

        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="DUPLICATE_SCAN",
                    action_id=task.task_id,
                    summary=f"全盘查重扫描: {valid_dir}",
                    status="RUNNING",
                )
            except Exception as e:
                logger.debug("Failed to link sub action: %s", e)

        asyncio.create_task(cls._execute_duplicate_scan(task.task_id, valid_dir, min_size_mb))

        return {
            "task_id": task.task_id,
            "status": "RUNNING",
            "message": f"Duplicate scan initiated for '{valid_dir}'",
        }

    @classmethod
    async def _execute_duplicate_scan(cls, task_id: str, scan_dir: str, min_size_mb: float):
        try:
            min_bytes = int(min_size_mb * 1024 * 1024)
            size_map: Dict[int, List[str]] = {}

            # 1. 第一级：文件物理体积精准初筛
            for root, _, files in os.walk(scan_dir):
                for f in files:
                    if task_engine.is_cancelled(task_id):
                        return
                    fp = os.path.join(root, f)
                    try:
                        sz = os.path.getsize(fp)
                        if sz >= min_bytes:
                            size_map.setdefault(sz, []).append(fp)
                    except OSError:
                        continue

            candidates = [paths for sz, paths in size_map.items() if len(paths) > 1]
            task_engine.update_progress(task_id, 30.0, {"candidate_groups": len(candidates)})

            # 2. 第二级：首尾 4KB 局部轻量哈希
            head_tail_map: Dict[str, List[str]] = {}
            for group in candidates:
                for fp in group:
                    if task_engine.is_cancelled(task_id):
                        return
                    try:
                        with open(fp, "rb") as f:
                            head = f.read(4096)
                            f.seek(max(0, os.path.getsize(fp) - 4096))
                            tail = f.read(4096)
                        ht_hash = hashlib.md5(head + tail).hexdigest()
                        head_tail_map.setdefault(ht_hash, []).append(fp)
                    except OSError:
                        continue

            second_candidates = [paths for h, paths in head_tail_map.items() if len(paths) > 1]
            task_engine.update_progress(task_id, 65.0)

            # 3. 第三级：极少数疑似文件全量 SHA256 校验
            duplicate_groups = []
            for group in second_candidates:
                full_hash_map: Dict[str, List[str]] = {}
                for fp in group:
                    if task_engine.is_cancelled(task_id):
                        return
                    sha = hashlib.sha256()
                    try:
                        with open(fp, "rb") as f:
                            while chunk := f.read(256 * 1024):
                                sha.update(chunk)
                        full_hash_map.setdefault(sha.hexdigest(), []).append(fp)
                    except OSError:
                        continue
                for h, paths in full_hash_map.items():
                    if len(paths) > 1:
                        duplicate_groups.append({
                            "sha256": h,
                            "size_mb": round(os.path.getsize(paths[0]) / (1024 * 1024), 2),
                            "files": paths,
                        })

            task_engine.complete_task(task_id, {"duplicate_groups_count": len(duplicate_groups), "duplicates": duplicate_groups})
        except Exception as e:
            logger.error("Duplicate scan failed for task %s: %s", task_id, e)
            task_engine.fail_task(task_id, str(e))

    @classmethod
    def extract_archive(
        cls,
        archive_path: str,
        dest_dir: Optional[str] = None,
        password: Optional[str] = None,
        remove_after_extract: bool = False,
        agent_task_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """解压压缩包（支持 zip/rar/7z/tar，后台异步执行）"""
        valid_arch = validate_sandbox_path(archive_path)
        if not os.path.isfile(valid_arch):
            raise FileNotFoundError(f"Archive '{archive_path}' does not exist")

        if not dest_dir:
            base, _ = os.path.splitext(valid_arch)
            dest_dir = base
        valid_dest = validate_sandbox_path(dest_dir)

        task = task_engine.create_task(
            task_type=TaskType.ARCHIVE_EXTRACT,
            detail={"archive": valid_arch, "dest": valid_dest, "agent_task_id": agent_task_id},
        )

        if agent_task_id:
            try:
                from nasio.services.agent_task_service import agent_task_service
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="ARCHIVE_EXTRACT",
                    action_id=task.task_id,
                    summary=f"解压文件: {os.path.basename(valid_arch)} -> {valid_dest}",
                    status="RUNNING",
                )
            except Exception as e:
                logger.debug("Failed to link sub action: %s", e)

        asyncio.create_task(
            cls._execute_extract(task.task_id, valid_arch, valid_dest, password, remove_after_extract)
        )

        return {
            "task_id": task.task_id,
            "status": "RUNNING",
            "message": f"Extraction job started for '{valid_arch}'",
        }

    @classmethod
    async def _execute_extract(cls, task_id: str, arch_path: str, dest_dir: str, password: Optional[str], remove_after: bool):
        try:
            ensure_nas_compatible_dir(dest_dir, reference_path=os.path.dirname(arch_path))
            # 优先使用系统 7z 命令 (支持 rar5, 7z, zip)
            cmd = ["7z", "x", f"-o{dest_dir}", "-y", arch_path]
            if password:
                cmd.append(f"-p{password}")

            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()

            if proc.returncode != 0:
                # 备选：若是 zip，尝试 Python 原生 zipfile 解压并修复编码
                if zipfile.is_zipfile(arch_path):
                    with zipfile.ZipFile(arch_path, "r") as zf:
                        for member in zf.infolist():
                            # 修复文件名编码
                            try:
                                filename = member.filename.encode("cp437").decode("gbk")
                            except Exception:
                                filename = member.filename
                            target_file = os.path.join(dest_dir, filename)
                            if member.is_dir():
                                ensure_nas_compatible_dir(target_file, reference_path=dest_dir)
                            else:
                                ensure_nas_compatible_dir(os.path.dirname(target_file), reference_path=dest_dir)
                                with zf.open(member) as source, open(target_file, "wb") as target:
                                    shutil.copyfileobj(source, target)
                                apply_nas_permissions(target_file, reference_path=dest_dir)
                else:
                    raise RuntimeError(f"7z extraction failed: {stderr.decode(errors='ignore')}")

            if remove_after and os.path.exists(arch_path):
                os.remove(arch_path)

            task_engine.complete_task(task_id, {"extracted_to": dest_dir, "archive": arch_path})
        except Exception as e:
            logger.error("Extraction failed for task %s: %s", task_id, e)
            task_engine.fail_task(task_id, str(e))

    @classmethod
    def _cn_num_to_int(cls, text: str) -> int:
        """将阿拉伯数字或中文数字（如 一、二、三、十、十二）转为整数季数"""
        text = text.strip()
        if text.isdigit():
            return max(1, int(text))
        cn_map = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "壹": 1, "贰": 2, "叁": 3, "肆": 4}
        if text == "十":
            return 10
        if text.startswith("十") and len(text) == 2:
            return 10 + cn_map.get(text[1], 0)
        if "十" in text:
            parts = text.split("十")
            tens = cn_map.get(parts[0], 1) if parts[0] else 1
            ones = cn_map.get(parts[1], 0) if len(parts) > 1 and parts[1] else 0
            return tens * 10 + ones
        return cn_map.get(text, 1)

    @classmethod
    def _is_quarter_category_dir(cls, dirname: str) -> bool:
        """识别是否为季度分类目录（如 '2026.7月新番'、'2026年7月新番'、'2025.10'、'2026春季新番'）"""
        name = dirname.strip()
        patterns = [
            r"^\d{4}\s*[.年/_-]\s*\d{1,2}\s*(?:月)?\s*(?:新番|番剧|动漫|动画)?$",
            r"^\d{4}\s*(?:年)?\s*(?:春|夏|秋|冬)(?:季)?\s*(?:新番|番剧|动漫|动画)?$",
            r"^(?:1月|4月|7月|10月)\s*(?:新番|番剧)$",
        ]
        return any(re.match(p, name, re.I) for p in patterns)

    @classmethod
    def _parse_pure_season_dir(cls, dirname: str) -> Optional[int]:
        """识别纯季度子目录名（如 'S1', 'S02', 'Season 1', '第1季', '第二季'）"""
        name = dirname.strip()
        m1 = re.match(r"^(?:S|Season\s*)0*([1-9]\d?)$", name, re.I)
        if m1:
            return int(m1.group(1))
        m2 = re.match(r"^第\s*([0-9]+|[一二三四五六七八九十两壹贰叁肆]+)\s*[季期部]$", name)
        if m2:
            return cls._cn_num_to_int(m2.group(1))
        return None

    @classmethod
    def _parse_series_and_season(cls, folder_name: str) -> Tuple[str, int, bool]:
        """
        从剧集目录名提取 (规范剧集名, 季数编号, 是否显式包含季数标识)。
        例如：
        - '碧蓝之海 第3季' -> ('碧蓝之海', 3, True)
        - '无职转生 第二季' -> ('无职转生', 2, True)
        - '[LoliHouse] Grand Blue S2 [WebRip 1080p]' -> ('Grand Blue', 2, True)
        - '猫与龙' -> ('猫与龙', 1, False)
        """
        raw = folder_name.strip()

        # 若目录名带有字幕组/压制组方括号前缀或技术后缀，先尝试剥离前导与尾部方括号标签
        cleaned = raw
        if cleaned.startswith("["):
            cleaned = re.sub(r"^(?:\[[^\]]+\]\s*)+", "", cleaned).strip()
            cleaned = re.sub(r"(?:\s*\[[^\]]+\])+$", "", cleaned).strip()
        if not cleaned:
            cleaned = raw

        # 1. 匹配中文季数标识：如 "第3季", "第二季", "第01期" (可选后缀 Part 2 等)
        m_cn = re.search(
            r"[\s._-]*第\s*([0-9]+|[一二三四五六七八九十两壹贰叁肆]+)\s*[季期部](?:\s*(?:Part\s*\d+|上半|下半))?\s*$",
            cleaned,
            re.I,
        )
        if m_cn:
            series = cleaned[: m_cn.start()].strip(" ._-")
            season = cls._cn_num_to_int(m_cn.group(1))
            if series:
                return series, season, True

        # 2. 匹配英文/标准季数标识：如 "S3", "S02", "Season 2", "2nd Season"
        m_en = re.search(
            r"(?:[\s._-]+)(?:(?:S|Season\s*)0*([1-9]\d?)|([1-9])(?:st|nd|rd|th)\s+Season)(?:\s*(?:Part\s*\d+))?\s*$",
            cleaned,
            re.I,
        )
        if m_en:
            series = cleaned[: m_en.start()].strip(" ._-")
            s_str = m_en.group(1) or m_en.group(2)
            season = int(s_str)
            if series:
                return series, season, True

        # 3. 匹配末尾罗马数字季数：如 "Overlord IV", "碧蓝之海 II"
        roman_map = {"II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6}
        m_rm = re.search(r"\s+(II|III|IV|V|VI)\s*$", cleaned)
        if m_rm:
            series = cleaned[: m_rm.start()].strip(" ._-")
            season = roman_map[m_rm.group(1)]
            if series:
                return series, season, True

        return cleaned, 1, False

    @classmethod
    def organize_series_seasons(
        cls,
        root_dir: str,
        target_dir: Optional[str] = None,
        season_folder_template: str = "S{season}",
        scan_quarter_subdirs: bool = True,
        flatten_episode_subdirs: bool = True,
        remove_empty_dirs: bool = True,
        conflict_resolution: str = "rename_suffix",
        dry_run: bool = True,
    ) -> Dict[str, Any]:
        """
        扫描目标目录下的动漫/剧集文件夹，识别相同剧集的不同季（如 第1季/第2季/S1/S2 等），
        统一归并整理至 '<target_dir>/<剧集名>/S1/<具体的剧集文件>' 标准多级目录结构，
        并自动对单集子目录进行向上扁平化提取、伴随字体包去重及空源目录安全软删除。
        """
        valid_root = validate_sandbox_path(root_dir)
        cls._assert_dir_accessible(root_dir, valid_root)

        if target_dir:
            valid_target = validate_sandbox_path(target_dir)
        else:
            valid_target = valid_root

        valid_root = os.path.abspath(valid_root)
        valid_target = os.path.abspath(valid_target)

        # 收集待整理的剧集季度目录项: List[Dict{source_dir, series_name, season_num, quarter_dir}]
        candidate_items: List[Dict[str, Any]] = []
        quarter_dirs_scanned: List[str] = []

        def collect_from_container(container_dir: str, quarter_parent: Optional[str] = None):
            try:
                entries = sorted(os.scandir(container_dir), key=lambda e: e.name.lower())
            except PermissionError as e:
                if container_dir == valid_root:
                    raise PermissionError(f"Permission denied scanning '{root_dir}': {e}") from e
                return

            for entry in entries:
                if not entry.is_dir() or entry.name.startswith("."):
                    continue

                # 若是季度分类目录（如 2026.7月新番）且开启了穿透扫描
                if quarter_parent is None and scan_quarter_subdirs and cls._is_quarter_category_dir(entry.name):
                    quarter_dirs_scanned.append(entry.path)
                    collect_from_container(entry.path, quarter_parent=entry.path)
                    continue

                # 检查该目录内部是否已经是按纯季度命名的子目录（如 剧集名/S1, 剧集名/第2季）
                try:
                    sub_entries = [e for e in os.scandir(entry.path) if e.is_dir() and not e.name.startswith(".")]
                except PermissionError:
                    sub_entries = []

                pure_season_subs = []
                for sub in sub_entries:
                    s_num = cls._parse_pure_season_dir(sub.name)
                    if s_num is not None:
                        pure_season_subs.append((sub.path, s_num))

                if pure_season_subs:
                    base_series, _, _ = cls._parse_series_and_season(entry.name)
                    for sub_path, s_num in pure_season_subs:
                        candidate_items.append({
                            "source_dir": sub_path,
                            "series_name": base_series,
                            "season_num": s_num,
                            "quarter_dir": quarter_parent,
                        })
                    # 检查该剧集主目录下是否还直接散落着视频文件
                    try:
                        direct_files = [
                            e.name for e in os.scandir(entry.path)
                            if e.is_file() and not e.name.startswith(".")
                        ]
                    except PermissionError:
                        direct_files = []
                    if direct_files:
                        candidate_items.append({
                            "source_dir": entry.path,
                            "series_name": base_series,
                            "season_num": 1,
                            "quarter_dir": quarter_parent,
                            "direct_files_only": True,
                        })
                else:
                    series_name, season_num, _ = cls._parse_series_and_season(entry.name)
                    candidate_items.append({
                        "source_dir": entry.path,
                        "series_name": series_name,
                        "season_num": season_num,
                        "quarter_dir": quarter_parent,
                    })

        collect_from_container(valid_root)

        series_summary: Dict[str, List[str]] = {}
        season_results = []
        total_files_moved = 0
        total_companions_deduped = 0
        total_dirs_removed = 0
        removed_source_dirs = []
        warnings = []
        all_movements: List[Dict[str, str]] = []
        all_trash_ids: List[str] = []

        junk_names = {".ds_store", "thumbs.db", "desktop.ini"}

        for item in candidate_items:
            src_dir = os.path.abspath(item["source_dir"])
            series_name = item["series_name"]
            season_num = item["season_num"]
            season_folder = season_folder_template.format(season=season_num)
            dst_season_dir = os.path.abspath(os.path.join(valid_target, series_name, season_folder))

            series_summary.setdefault(series_name, [])
            if season_folder not in series_summary[series_name]:
                series_summary[series_name].append(season_folder)

            max_walk_depth = 0 if item.get("direct_files_only") else (5 if flatten_episode_subdirs else 0)

            flat_res = cls.flatten_directory(
                source_dir=src_dir,
                target_dir=dst_season_dir,
                remove_empty_dirs=remove_empty_dirs,
                dedup_companions=True,
                conflict_resolution=conflict_resolution,
                max_depth=max_walk_depth,
                dry_run=dry_run,
                _record_tx=False,
            )

            total_files_moved += flat_res["total_moved"]
            total_companions_deduped += flat_res["total_deduped"]
            total_dirs_removed += flat_res["total_dirs_removed"]
            warnings.extend(flat_res.get("warnings", []))
            all_movements.extend(flat_res.get("moved_files", []))
            all_trash_ids.extend(flat_res.get("_trash_ids", []))

            # 判断源目录本身是否应当在迁移后软删除（当源目录不是目标目录本身、也不是目标目录的父目录时）
            is_ancestor_of_dst = (os.path.commonpath([src_dir, dst_season_dir]) == src_dir)
            src_removed = False
            if remove_empty_dirs and not is_ancestor_of_dst and len(flat_res.get("skipped_files", [])) == 0:
                if dry_run:
                    src_removed = True
                    total_dirs_removed += 1
                    removed_source_dirs.append(src_dir)
                else:
                    if os.path.isdir(src_dir):
                        remaining = [
                            e.name for e in os.scandir(src_dir)
                            if e.name.lower() not in junk_names and not e.name.startswith("._")
                        ]
                        if not remaining:
                            for junk in os.listdir(src_dir):
                                try:
                                    os.remove(os.path.join(src_dir, junk))
                                except OSError:
                                    pass
                            try:
                                del_res = TrashService.safe_delete([src_dir], reason="Consolidated series season directory")
                                all_trash_ids.extend([r["trash_id"] for r in del_res if r.get("success") and r.get("trash_id")])
                                src_removed = True
                                total_dirs_removed += 1
                                removed_source_dirs.append(src_dir)
                            except Exception as e:
                                warnings.append(f"Failed to soft delete source dir '{src_dir}': {e}")

            season_results.append({
                "series_name": series_name,
                "season": season_folder,
                "source_dir": src_dir,
                "target_dir": dst_season_dir,
                "files_moved": flat_res["total_moved"],
                "companions_deduped": flat_res["total_deduped"],
                "source_dir_removed": src_removed,
            })

        # 若扫描了季度分类目录（如 2026.7月新番）且已完全清空，顺带清理空季度分类壳目录
        if remove_empty_dirs and not dry_run:
            for q_dir in quarter_dirs_scanned:
                if os.path.isdir(q_dir):
                    remaining = [
                        e.name for e in os.scandir(q_dir)
                        if e.name.lower() not in junk_names and not e.name.startswith("._")
                    ]
                    if not remaining:
                        for junk in os.listdir(q_dir):
                            try:
                                os.remove(os.path.join(q_dir, junk))
                            except OSError:
                                pass
                        try:
                            del_res = TrashService.safe_delete([q_dir], reason="Empty quarter category directory after series consolidation")
                            all_trash_ids.extend([r["trash_id"] for r in del_res if r.get("success") and r.get("trash_id")])
                            total_dirs_removed += 1
                            removed_source_dirs.append(q_dir)
                        except Exception as e:
                            warnings.append(f"Failed to soft delete quarter dir '{q_dir}': {e}")

        tx_id = None
        if not dry_run and (all_movements or all_trash_ids):
            try:
                from nasio.services.transaction_service import transaction_service
                tx = transaction_service.record_transaction(
                    operation_type="SERIES_ORGANIZE",
                    summary=f"多季剧集整理 {valid_root} (共 {len(series_summary)} 部剧集, 移动 {total_files_moved} 个文件)",
                    movements=all_movements,
                    trash_ids=all_trash_ids,
                )
                if tx:
                    tx_id = tx.transaction_id
            except Exception as e:
                logger.warning("Failed to record organize_series_seasons transaction: %s", e)

        res = {
            "dry_run": dry_run,
            "root_dir": valid_root,
            "target_dir": valid_target,
            "total_series_count": len(series_summary),
            "total_seasons_processed": len(season_results),
            "total_files_moved": total_files_moved,
            "total_companions_deduped": total_companions_deduped,
            "total_dirs_removed": total_dirs_removed,
            "series_structure": {k: sorted(v) for k, v in series_summary.items()},
            "season_details": season_results,
            "removed_source_dirs": removed_source_dirs,
            "warnings": warnings,
        }
        if tx_id:
            res["transaction_id"] = tx_id
        return res

    # ==========================================
    # AI 原生增强：Token 友好感知与智能垃圾清理
    # ==========================================

    @classmethod
    def get_directory_digest(cls, dir_path: str, max_depth: int = 4) -> Dict[str, Any]:
        """
        生成目录结构智能统计摘要（Token 友好型感知）：
        无需输出成千上万个文件名，仅用极简结构化摘要返回：
        子目录数、文件总数、总大小、文件类型(扩展名)分布、一级子文件夹体积分布、疑似垃圾广告文件数及未完成下载数。
        """
        valid_dir = validate_sandbox_path(dir_path)
        cls._assert_dir_accessible(dir_path, valid_dir)

        total_files = 0
        total_subdirs = 0
        total_bytes = 0
        ext_stats: Dict[str, Dict[str, int]] = {}
        top_subdir_stats: Dict[str, Dict[str, int]] = {}
        incomplete_count = 0
        suspected_rubbish_count = 0
        oldest_mtime: Optional[float] = None
        newest_mtime: Optional[float] = None

        incomplete_exts = {"!qb", "part", "crdownload", "tmp"}
        rubbish_exts = {"url", "htm", "html", "mht", "lnk", "chm"}
        junk_names = {".ds_store", "thumbs.db", "desktop.ini"}
        ad_keywords = ["首发", "最新地址", "备用域名", "防走失", "扫码", "宣传", "论坛", "发布页", "福利", "赌场", "博彩"]

        root_depth = valid_dir.rstrip(os.sep).count(os.sep)

        for current_root, dirs, files in os.walk(valid_dir):
            curr_depth = current_root.count(os.sep) - root_depth
            if curr_depth >= max_depth:
                dirs.clear()

            # 排除隐藏系统目录
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            total_subdirs += len(dirs)

            # 归属的一级子目录名称
            rel_dir = os.path.relpath(current_root, valid_dir)
            top_sub_name = rel_dir.split(os.sep)[0] if rel_dir != "." else "(根目录直属)"
            top_entry = top_subdir_stats.setdefault(top_sub_name, {"files": 0, "bytes": 0})

            for f in files:
                lower_f = f.lower()
                fp = os.path.join(current_root, f)
                try:
                    st = os.stat(fp)
                except OSError:
                    continue

                total_files += 1
                total_bytes += st.st_size
                top_entry["files"] += 1
                top_entry["bytes"] += st.st_size

                if oldest_mtime is None or st.st_mtime < oldest_mtime:
                    oldest_mtime = st.st_mtime
                if newest_mtime is None or st.st_mtime > newest_mtime:
                    newest_mtime = st.st_mtime

                _, raw_ext = os.path.splitext(f)
                ext = raw_ext.lower().lstrip(".") or "(无扩展名)"
                ext_entry = ext_stats.setdefault(ext, {"count": 0, "bytes": 0})
                ext_entry["count"] += 1
                ext_entry["bytes"] += st.st_size

                if ext in incomplete_exts:
                    incomplete_count += 1

                if lower_f in junk_names or ext in rubbish_exts:
                    suspected_rubbish_count += 1
                elif st.st_size < 2 * 1024 * 1024 and any(k in lower_f for k in ad_keywords):
                    suspected_rubbish_count += 1

        ext_breakdown = [
            {
                "extension": f".{k}" if k != "(无扩展名)" else k,
                "count": v["count"],
                "size_mb": round(v["bytes"] / (1024 * 1024), 2),
            }
            for k, v in sorted(ext_stats.items(), key=lambda x: x[1]["bytes"], reverse=True)[:12]
        ]

        top_subdirs = [
            {
                "name": k,
                "file_count": v["files"],
                "size_mb": round(v["bytes"] / (1024 * 1024), 2),
            }
            for k, v in sorted(top_subdir_stats.items(), key=lambda x: x[1]["bytes"], reverse=True)[:15]
        ]

        return {
            "dir_path": valid_dir,
            "total_files": total_files,
            "total_subdirs": total_subdirs,
            "total_size_mb": round(total_bytes / (1024 * 1024), 2),
            "total_size_gb": round(total_bytes / (1024 ** 3), 2),
            "incomplete_downloads_count": incomplete_count,
            "suspected_rubbish_count": suspected_rubbish_count,
            "oldest_modified": datetime.fromtimestamp(oldest_mtime).isoformat() if oldest_mtime else None,
            "newest_modified": datetime.fromtimestamp(newest_mtime).isoformat() if newest_mtime else None,
            "extension_breakdown": ext_breakdown,
            "top_level_breakdown": top_subdirs,
        }

    @classmethod
    def sample_directory_files(
        cls,
        dir_path: str,
        sample_per_group: int = 3,
        max_depth: int = 3,
    ) -> Dict[str, Any]:
        """
        典型文件样本嗅探（供 AI 推断命名规律与编写正则，极大节省 Token）：
        按 (相对目录, 文件扩展名) 分组，每组仅抽取 sample_per_group 个代表性文件名。
        """
        valid_dir = validate_sandbox_path(dir_path)
        cls._assert_dir_accessible(dir_path, valid_dir)

        sample_per_group = max(1, min(sample_per_group, 10))
        groups: Dict[Tuple[str, str], Dict[str, Any]] = {}
        root_depth = valid_dir.rstrip(os.sep).count(os.sep)

        for current_root, dirs, files in os.walk(valid_dir):
            curr_depth = current_root.count(os.sep) - root_depth
            if curr_depth >= max_depth:
                dirs.clear()
            dirs[:] = [d for d in dirs if not d.startswith(".")]

            rel_dir = os.path.relpath(current_root, valid_dir)
            for f in sorted(files):
                if f.startswith("."):
                    continue
                _, raw_ext = os.path.splitext(f)
                ext = raw_ext.lower() or "(no_ext)"
                key = (rel_dir, ext)
                grp = groups.setdefault(
                    key,
                    {
                        "relative_dir": rel_dir,
                        "extension": ext,
                        "total_in_group": 0,
                        "sample_filenames": [],
                    },
                )
                grp["total_in_group"] += 1
                if len(grp["sample_filenames"]) < sample_per_group:
                    grp["sample_filenames"].append(f)

        sorted_groups = sorted(groups.values(), key=lambda x: x["total_in_group"], reverse=True)[:30]
        return {
            "dir_path": valid_dir,
            "total_groups": len(groups),
            "groups_returned": len(sorted_groups),
            "samples": sorted_groups,
        }

    @classmethod
    def clean_resource_rubbish(
        cls,
        dir_path: str,
        max_depth: int = 5,
        dry_run: bool = True,
    ) -> Dict[str, Any]:
        """
        领域级复合清理工具：自动识别并安全软删除 BT/PT/压缩包解压目录中的发布站广告、快捷方式、网页链接与系统垃圾文件。
        """
        valid_dir = validate_sandbox_path(dir_path)
        cls._assert_dir_accessible(dir_path, valid_dir)

        rubbish_exts = {"url", "htm", "html", "mht", "lnk", "chm"}
        junk_names = {".ds_store", "thumbs.db", "desktop.ini"}
        ad_keywords = [
            "首发", "最新地址", "备用域名", "防走失", "扫码", "宣传", "论坛", "发布页",
            "福利", "赌场", "博彩", "美女荷官", "裸聊", "同城", "关注公众号", "免費",
        ]

        matched_files: List[Dict[str, Any]] = []
        root_depth = valid_dir.rstrip(os.sep).count(os.sep)

        for current_root, dirs, files in os.walk(valid_dir):
            curr_depth = current_root.count(os.sep) - root_depth
            if curr_depth >= max_depth:
                dirs.clear()
            dirs[:] = [d for d in dirs if not d.startswith(".")]

            for f in files:
                fp = os.path.join(current_root, f)
                lower_f = f.lower()
                try:
                    st = os.stat(fp)
                except OSError:
                    continue

                _, raw_ext = os.path.splitext(f)
                ext = raw_ext.lower().lstrip(".")
                reason = None

                if lower_f in junk_names or lower_f.startswith("._"):
                    reason = "系统冗余缓存文件"
                elif ext in rubbish_exts:
                    reason = f"网页/快捷方式外链文件 (.{ext})"
                elif ext == "txt" and st.st_size < 100 * 1024 and any(k in lower_f for k in ad_keywords):
                    reason = "疑似发布站宣传文本"
                elif ext in {"jpg", "jpeg", "png", "gif", "webp", "mp4"} and st.st_size < 5 * 1024 * 1024 and any(k in lower_f for k in ad_keywords):
                    reason = "疑似推广广告媒体文件"

                if reason:
                    matched_files.append({
                        "path": fp,
                        "name": f,
                        "size_kb": round(st.st_size / 1024, 2),
                        "reason": reason,
                    })

        tx_id = None
        trash_ids: List[str] = []
        if not dry_run and matched_files:
            paths_to_del = [m["path"] for m in matched_files]
            del_res = TrashService.safe_delete(paths_to_del, reason="AI clean_resource_rubbish 广告垃圾清理")
            trash_ids = [r["trash_id"] for r in del_res if r.get("success") and r.get("trash_id")]

            if trash_ids:
                try:
                    from nasio.services.transaction_service import transaction_service
                    tx = transaction_service.record_transaction(
                        operation_type="CLEAN_RUBBISH",
                        summary=f"清理资源广告与垃圾文件: {valid_dir} (共清理 {len(trash_ids)} 个文件)",
                        trash_ids=trash_ids,
                    )
                    if tx:
                        tx_id = tx.transaction_id
                except Exception as e:
                    logger.warning("Failed to record clean_resource_rubbish transaction: %s", e)

        res = {
            "dry_run": dry_run,
            "dir_path": valid_dir,
            "total_matched": len(matched_files),
            "cleaned_count": len(trash_ids) if not dry_run else 0,
            "matched_files": matched_files,
        }
        if tx_id:
            res["transaction_id"] = tx_id
        return res


