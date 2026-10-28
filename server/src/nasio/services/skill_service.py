import os
import re
import yaml
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional
from nasio.core.config import CONFIG_PATH

logger = logging.getLogger("nasio.skills")

# 默认技能持久化根目录位于 data/skills
SKILLS_DIR = os.environ.get("SKILLS_DIR", os.path.join(os.path.dirname(CONFIG_PATH), "skills"))


def _ensure_skills_dir() -> str:
    os.makedirs(SKILLS_DIR, exist_ok=True)
    return SKILLS_DIR


def _sanitize_skill_name(name: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_\-\.]", "_", name.strip())
    if not cleaned:
        raise ValueError("技能标识名无效，必须包含合法字符")
    return cleaned


def _parse_skill_file(file_path: str, skill_name: str) -> Dict[str, Any]:
    """解析带有 YAML Frontmatter 的 SKILL.md 文件"""
    with open(file_path, "r", encoding="utf-8") as f:
        raw_text = f.read()

    frontmatter = {}
    markdown_body = raw_text

    # 匹配顶部 --- 包裹的 YAML 元数据
    pattern = r"^---\s*\r?\n(.*?)\r?\n---\s*\r?\n(.*)$"
    match = re.search(pattern, raw_text, re.DOTALL)
    if match:
        yaml_content = match.group(1)
        markdown_body = match.group(2)
        try:
            parsed = yaml.safe_load(yaml_content)
            if isinstance(parsed, dict):
                frontmatter = parsed
        except Exception as e:
            logger.warning("解析技能 Frontmatter 异常 %s: %s", file_path, e)

    stat = os.stat(file_path)
    updated_at = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")

    name = frontmatter.get("name") or skill_name
    description = frontmatter.get("description") or ""
    tags = frontmatter.get("tags") or []
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]

    version = str(frontmatter.get("version", "1.0.0"))

    return {
        "name": str(name),
        "description": str(description).strip(),
        "tags": list(tags),
        "version": version,
        "updated_at": updated_at,
        "file_size": stat.st_size,
        "content": raw_text,
        "body": markdown_body.strip(),
        "path": file_path,
    }


class SkillService:
    @staticmethod
    def get_skills_dir() -> str:
        return _ensure_skills_dir()

    @classmethod
    def list_skills(cls) -> List[Dict[str, Any]]:
        """获取服务端已持久化的全部技能列表（摘要元信息）"""
        skills_dir = _ensure_skills_dir()
        skills = []

        if not os.path.exists(skills_dir):
            return skills

        for entry in os.listdir(skills_dir):
            entry_path = os.path.join(skills_dir, entry)
            target_file = None

            if os.path.isdir(entry_path):
                # 优先匹配目录下的 SKILL.md，其次匹配 skill.md 或任意 .md
                candidate = os.path.join(entry_path, "SKILL.md")
                candidate_lower = os.path.join(entry_path, "skill.md")
                if os.path.isfile(candidate):
                    target_file = candidate
                elif os.path.isfile(candidate_lower):
                    target_file = candidate_lower
                else:
                    for sub in os.listdir(entry_path):
                        if sub.endswith(".md"):
                            target_file = os.path.join(entry_path, sub)
                            break
            elif entry.endswith(".md"):
                target_file = entry_path

            if target_file and os.path.isfile(target_file):
                try:
                    meta = _parse_skill_file(target_file, entry)
                    # 列表接口不返回超大 body，节省网络传输
                    summary_item = {
                        "name": meta["name"],
                        "description": meta["description"],
                        "tags": meta["tags"],
                        "version": meta["version"],
                        "updated_at": meta["updated_at"],
                        "file_size": meta["file_size"],
                    }
                    skills.append(summary_item)
                except Exception as e:
                    logger.error("读取技能失败 %s: %s", target_file, e)

        # 按最后修改时间倒序排列
        skills.sort(key=lambda x: x.get("updated_at", ""), reverse=True)
        return skills

    @classmethod
    def get_skill(cls, name: str) -> Optional[Dict[str, Any]]:
        """获取单个技能的完整内容及元数据"""
        skills_dir = _ensure_skills_dir()
        sanitized = _sanitize_skill_name(name)

        # 候选查找路径
        candidate_paths = [
            os.path.join(skills_dir, sanitized, "SKILL.md"),
            os.path.join(skills_dir, sanitized, "skill.md"),
            os.path.join(skills_dir, f"{sanitized}.md"),
        ]

        target_file = None
        for p in candidate_paths:
            if os.path.isfile(p):
                target_file = p
                break

        # 若未命中，尝试忽略大小写查找子目录
        if not target_file and os.path.exists(skills_dir):
            for d in os.listdir(skills_dir):
                if d.lower() == sanitized.lower():
                    sub_skill = os.path.join(skills_dir, d, "SKILL.md")
                    if os.path.isfile(sub_skill):
                        target_file = sub_skill
                        break

        if not target_file:
            return None

        return _parse_skill_file(target_file, sanitized)

    @classmethod
    def save_or_update_skill(
        cls,
        name: str,
        description: str,
        content: str,
        tags: Optional[List[str]] = None,
        version: str = "1.0.0",
    ) -> Dict[str, Any]:
        """
        保存或更新技能，保证标准 Frontmatter 规范，并原子写入 data/skills/<name>/SKILL.md
        """
        skills_dir = _ensure_skills_dir()
        sanitized = _sanitize_skill_name(name)
        target_dir = os.path.join(skills_dir, sanitized)
        os.makedirs(target_dir, exist_ok=True)
        target_file = os.path.join(target_dir, "SKILL.md")

        tags = tags or []
        body_content = content.strip()

        # 检查是否已有 frontmatter
        pattern = r"^---\s*\r?\n(.*?)\r?\n---\s*\r?\n(.*)$"
        match = re.search(pattern, body_content, re.DOTALL)
        if match:
            existing_yaml = match.group(1)
            body_content = match.group(2).strip()
            try:
                parsed_fm = yaml.safe_load(existing_yaml)
                if isinstance(parsed_fm, dict):
                    if not description and parsed_fm.get("description"):
                        description = parsed_fm.get("description")
                    if not tags and parsed_fm.get("tags"):
                        parsed_tags = parsed_fm.get("tags")
                        tags = [parsed_tags] if isinstance(parsed_tags, str) else list(parsed_tags)
                    if parsed_fm.get("version"):
                        version = str(parsed_fm.get("version"))
            except Exception:
                pass

        # 组装标准 Frontmatter
        fm_dict = {
            "name": sanitized,
            "description": description.strip(),
        }
        if tags:
            fm_dict["tags"] = tags
        if version:
            fm_dict["version"] = version

        fm_yaml = yaml.dump(fm_dict, allow_unicode=True, sort_keys=False).strip()
        final_markdown = f"---\n{fm_yaml}\n---\n\n{body_content}\n"

        # 原子落盘
        temp_file = f"{target_file}.tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            f.write(final_markdown)

        if os.path.exists(target_file):
            os.remove(target_file)
        os.rename(temp_file, target_file)

        logger.info("技能已成功落盘: %s (%s)", sanitized, target_file)
        return _parse_skill_file(target_file, sanitized)

    @classmethod
    def delete_skill(cls, name: str) -> bool:
        """删除指定技能"""
        skills_dir = _ensure_skills_dir()
        sanitized = _sanitize_skill_name(name)
        target_dir = os.path.join(skills_dir, sanitized)

        deleted = False
        if os.path.isdir(target_dir):
            import shutil
            shutil.rmtree(target_dir)
            deleted = True

        single_file = os.path.join(skills_dir, f"{sanitized}.md")
        if os.path.isfile(single_file):
            os.remove(single_file)
            deleted = True

        return deleted


skill_service = SkillService()
