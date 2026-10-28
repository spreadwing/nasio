import os
import re
import json
import time
import uuid
import asyncio
import logging
import hashlib
import xml.etree.ElementTree as ET
from typing import List, Dict, Any, Optional, Union
from pydantic import BaseModel, Field
import httpx

from nasio.core.config import CONFIG_PATH
from nasio.core.security import validate_sandbox_path, ensure_nas_compatible_dir
from nasio.services.downloader_service import DownloaderService
from nasio.services.agent_task_service import agent_task_service

logger = logging.getLogger("nasio.rss")

DATA_DIR = os.path.dirname(CONFIG_PATH)
RSS_SUBSCRIPTIONS_FILE = os.path.join(DATA_DIR, "rss_subscriptions.json")


class RssFilterRule(BaseModel):
    tag: str = "title"  # XML 标签名，如 title, enclosure, category, description 等
    attribute: Optional[str] = None  # 属性名，如 type, url, length；空表示匹配标签内部文本
    pattern: str = ""  # 正则表达式
    mode: str = "INCLUDE"  # INCLUDE (包含/必须匹配) 或 EXCLUDE (排除/不得匹配)


# 常见字幕语言别名与正则映射表
SUBTITLE_LANGUAGE_MAP: Dict[str, str] = {
    # 简体中文 / 简日双语 / 简中
    "CHS": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "GB": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "SC": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "SIMPLIFIED": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "简": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "简中": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "简日": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "简体": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    "简体中文": r"(简[中日]?|简体|CHS|GB|SC|JPSC|简日双语|简体中文|简繁|双语)",
    # 繁体中文 / 繁日双语 / 繁中
    "CHT": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "TC": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "BIG5": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "TRADITIONAL": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "繁": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "繁中": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁体中文|繁體中文|简繁|双语)",
    "繁日": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "繁体": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "繁体中文": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    "繁體中文": r"(繁[中日]?|繁体|CHT|BIG5|TC|JPTC|繁日双语|繁體中文|简繁|双语)",
    # 双语
    "BIL": r"(双语|简繁|CHS[&/]CHT|GB[/&]BIG5|BILINGUAL)",
    "BILINGUAL": r"(双语|简繁|CHS[&/]CHT|GB[/&]BIG5|BILINGUAL)",
    "双语": r"(双语|简繁|CHS[&/]CHT|GB[/&]BIG5|BILINGUAL)",
    "简繁": r"(双语|简繁|CHS[&/]CHT|GB[/&]BIG5|BILINGUAL)",
    # 日文 / RAW
    "JPN": r"(日[语文]|JPN|RAW|无字)",
    "RAW": r"(日[语文]|JPN|RAW|无字)",
    "日文": r"(日[语文]|JPN|RAW|无字)",
}


def resolve_subtitle_pattern(lang_or_pattern: str) -> str:
    """根据字幕语言简称/别名返回匹配正则；若非内置别名则作为自定义正则直接返回"""
    key = lang_or_pattern.strip().upper()
    if key in SUBTITLE_LANGUAGE_MAP:
        return SUBTITLE_LANGUAGE_MAP[key]
    raw_key = lang_or_pattern.strip()
    if raw_key in SUBTITLE_LANGUAGE_MAP:
        return SUBTITLE_LANGUAGE_MAP[raw_key]
    return raw_key


def normalize_filter_rules(
    filter_rules_input: Optional[Union[str, List[Any], Dict[str, Any]]] = None,
    subtitle_language: Optional[str] = None,
) -> List[RssFilterRule]:
    """
    统一解析并标准化过滤规则：
    - 支持 str（JSON 字符串、纯正则字符串、单条规则）
    - 支持 List（List[RssFilterRule], List[dict], List[str] 纯正则或字幕标识）
    - 支持 Dict（单条规则）
    - 支持 subtitle_language（简中、繁中、CHS、CHT 等预设直接转换为 title 包含规则）
    - 兼容 dict 缺少 tag 时默认 tag="title"、mode="INCLUDE"
    - 兼容条目中指定 subtitle_language / language / tag="subtitle" 等语法糖
    """
    rules: List[RssFilterRule] = []
    parsed_items = []

    if filter_rules_input is not None:
        if isinstance(filter_rules_input, str):
            text = filter_rules_input.strip()
            if text:
                if (text.startswith("[") and text.endswith("]")) or (text.startswith("{") and text.endswith("}")):
                    try:
                        loaded = json.loads(text)
                        if isinstance(loaded, list):
                            parsed_items.extend(loaded)
                        elif isinstance(loaded, dict):
                            parsed_items.append(loaded)
                    except Exception:
                        parsed_items.append({"tag": "title", "pattern": text, "mode": "INCLUDE"})
                else:
                    parsed_items.append({"tag": "title", "pattern": text, "mode": "INCLUDE"})
        elif isinstance(filter_rules_input, list):
            parsed_items.extend(filter_rules_input)
        elif isinstance(filter_rules_input, dict):
            parsed_items.append(filter_rules_input)

    for item in parsed_items:
        if isinstance(item, RssFilterRule):
            rules.append(item)
        elif isinstance(item, dict):
            if "subtitle_language" in item or "language" in item:
                lang = item.get("subtitle_language") or item.get("language")
                pattern = resolve_subtitle_pattern(str(lang))
                mode = str(item.get("mode") or "INCLUDE").upper()
                rules.append(RssFilterRule(tag="title", pattern=pattern, mode=mode))
            elif str(item.get("tag", "")).lower() in ["subtitle", "language", "sub"]:
                pattern = resolve_subtitle_pattern(str(item.get("pattern", "")))
                mode = str(item.get("mode") or "INCLUDE").upper()
                rules.append(RssFilterRule(tag="title", pattern=pattern, mode=mode))
            else:
                tag = str(item.get("tag") or "title")
                pattern = str(item.get("pattern", "")).strip()
                if not pattern:
                    continue
                attribute = item.get("attribute")
                mode = str(item.get("mode") or "INCLUDE").upper()
                rules.append(RssFilterRule(tag=tag, attribute=attribute, pattern=pattern, mode=mode))
        elif isinstance(item, str):
            clean_str = item.strip()
            if not clean_str:
                continue
            pattern = resolve_subtitle_pattern(clean_str)
            rules.append(RssFilterRule(tag="title", pattern=pattern, mode="INCLUDE"))

    if subtitle_language and subtitle_language.strip():
        sub_pattern = resolve_subtitle_pattern(subtitle_language.strip())
        if not any(r.tag == "title" and r.pattern == sub_pattern for r in rules):
            rules.append(RssFilterRule(tag="title", pattern=sub_pattern, mode="INCLUDE"))

    return rules


def normalize_selected_guids(
    selected_guids_input: Optional[Union[str, List[Any]]] = None,
) -> Optional[List[str]]:
    """
    统一解析并标准化选摘 GUID 列表：
    - 支持 JSON 数组字符串 '["a", "b"]'
    - 支持逗号分隔字符串 'a, b'
    - 支持 List[str] 或 List[Any]
    """
    if selected_guids_input is None:
        return None
    if isinstance(selected_guids_input, list):
        return [str(g).strip() for g in selected_guids_input if str(g).strip()]
    if isinstance(selected_guids_input, str):
        text = selected_guids_input.strip()
        if not text:
            return None
        if text.startswith("[") and text.endswith("]"):
            try:
                loaded = json.loads(text)
                if isinstance(loaded, list):
                    return [str(g).strip() for g in loaded if str(g).strip()]
            except Exception:
                pass
        return [part.strip() for part in text.split(",") if part.strip()]
    return None


def normalize_url_extract_rule(
    rule_input: Optional[Union[str, Dict[str, Any]]] = None,
) -> Optional[Dict[str, str]]:
    """
    统一解析并标准化 URL 提取规则：
    - 支持 JSON 对象字符串 '{"tag": "enclosure", "attribute": "url"}'
    - 支持 Dict[str, str]
    """
    if rule_input is None:
        return None
    if isinstance(rule_input, dict):
        return {str(k): str(v) for k, v in rule_input.items()}
    if isinstance(rule_input, str):
        text = rule_input.strip()
        if not text:
            return None
        try:
            loaded = json.loads(text)
            if isinstance(loaded, dict):
                return {str(k): str(v) for k, v in loaded.items()}
        except Exception:
            pass
    return None


class RssItemPreview(BaseModel):
    guid: str
    title: str
    link: str
    download_url: str
    pub_date: str = ""
    matched: bool = True
    is_downloaded: bool = False
    tag_values: Dict[str, str] = Field(default_factory=dict)


class RssDownloadRecord(BaseModel):
    guid: str
    title: str
    download_url: str
    download_time: float = Field(default_factory=time.time)
    task_id: Optional[str] = None
    engine: str = "auto"
    status: str = "DISPATCHED"


class RssSubscriptionModel(BaseModel):
    rss_id: str
    title: str
    feed_url: str
    save_dir: str
    filter_rules: List[RssFilterRule] = Field(default_factory=list)
    url_extract_rule: Optional[Dict[str, str]] = None  # {"tag": "enclosure", "attribute": "url"}
    check_interval_minutes: int = 15
    download_engine: str = "auto"
    enabled: bool = True
    last_checked_at: float = 0.0
    last_error: Optional[str] = None
    total_downloaded_count: int = 0
    downloaded_guids: List[str] = Field(default_factory=list)
    download_history: List[RssDownloadRecord] = Field(default_factory=list)
    agent_task_id: Optional[str] = None
    subtitle_language: Optional[str] = None
    created_at: float = Field(default_factory=time.time)
    updated_at: float = Field(default_factory=time.time)


class RssService:
    _instance: Optional["RssService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._subscriptions = {}
            cls._instance._polling_task = None
            cls._instance._load_from_disk()
        return cls._instance

    def _load_from_disk(self):
        try:
            if os.path.exists(RSS_SUBSCRIPTIONS_FILE):
                with open(RSS_SUBSCRIPTIONS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data:
                        sub = RssSubscriptionModel(**item)
                        self._subscriptions[sub.rss_id] = sub
                logger.info("Loaded %d RSS subscriptions from %s", len(self._subscriptions), RSS_SUBSCRIPTIONS_FILE)
        except Exception as e:
            logger.warning("Failed to load RSS subscriptions from %s: %s", RSS_SUBSCRIPTIONS_FILE, e)

    def _save_to_disk(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            data_list = [s.model_dump() for s in self._subscriptions.values()]
            with open(RSS_SUBSCRIPTIONS_FILE, "w", encoding="utf-8") as f:
                json.dump(data_list, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error("Failed to save RSS subscriptions to %s: %s", RSS_SUBSCRIPTIONS_FILE, e)

    @classmethod
    async def fetch_feed_xml(cls, feed_url: str) -> str:
        """从指定 URL 获取 RSS / Atom XML 文本内容"""
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Nasio-RSS/1.0"
        }
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True, headers=headers) as client:
            resp = await client.get(feed_url)
            resp.raise_for_status()
            return resp.text

    @classmethod
    def _local_tag_name(cls, full_tag: str) -> str:
        """剥离 XML Namespace 提取本地标签名 (如 {http://...}item -> item)"""
        if "}" in full_tag:
            return full_tag.split("}", 1)[1]
        return full_tag

    @classmethod
    def _extract_download_url(
        cls,
        item_elem: ET.Element,
        url_extract_rule: Optional[Dict[str, str]] = None,
    ) -> str:
        """
        根据自定义规则或智能回退策略提取下载目标 URL:
        1. 若有 url_extract_rule (如 tag='enclosure', attribute='url')，优先读取；
        2. 默认探测 <enclosure url="..." /> 属性；
        3. 探测 <link rel="enclosure" href="..." /> 或 Atom <link href="..." />；
        4. 探测 <link> 文本；
        5. 探测 <guid> 文本 (若为有效 http/https/magnet 链接)。
        """
        if url_extract_rule:
            target_tag = url_extract_rule.get("tag", "").lower()
            target_attr = url_extract_rule.get("attribute", "")
            for child in item_elem:
                if cls._local_tag_name(child.tag).lower() == target_tag:
                    if target_attr:
                        val = child.attrib.get(target_attr, "")
                        if val:
                            return val.strip()
                    else:
                        val = (child.text or "").strip()
                        if val:
                            return val

        # 默认探测顺序 1: enclosure
        for child in item_elem:
            ltag = cls._local_tag_name(child.tag).lower()
            if ltag == "enclosure":
                url_attr = child.attrib.get("url") or child.attrib.get("href")
                if url_attr:
                    return url_attr.strip()

        # 默认探测顺序 2: link (考虑 Atom 语法与标准 RSS)
        for child in item_elem:
            ltag = cls._local_tag_name(child.tag).lower()
            if ltag == "link":
                # Atom: <link rel="enclosure" href="..." /> 或普通 <link href="..." />
                href = child.attrib.get("href")
                if href:
                    return href.strip()
                # 标准 RSS: <link>http://...</link>
                if child.text and child.text.strip():
                    return child.text.strip()

        # 默认探测顺序 3: guid
        for child in item_elem:
            ltag = cls._local_tag_name(child.tag).lower()
            if ltag in ["guid", "id"]:
                val = (child.text or "").strip()
                if val.startswith("http://") or val.startswith("https://") or val.startswith("magnet:?"):
                    return val

        return ""

    @classmethod
    def _evaluate_item_filters(
        cls,
        item_elem: ET.Element,
        filter_rules: List[RssFilterRule],
    ) -> bool:
        """
        判断单个条目是否符合所有正则规则（多条规则为 AND 逻辑）：
        - 每条规则指定 tag、可选的 attribute，以及 pattern 正则表达式与 mode (INCLUDE / EXCLUDE)
        """
        if not filter_rules:
            return True

        for rule in filter_rules:
            target_tag = rule.tag.strip().lower()
            target_attr = (rule.attribute or "").strip()
            pattern = rule.pattern
            mode = (rule.mode or "INCLUDE").upper()

            # 收集该条目中所有匹配 target_tag 的值
            values_to_test = []
            for child in item_elem:
                child_ltag = cls._local_tag_name(child.tag).lower()
                if child_ltag == target_tag or (":" in rule.tag and child.tag.endswith(rule.tag)):
                    if target_attr:
                        attr_val = child.attrib.get(target_attr)
                        if attr_val is not None:
                            values_to_test.append(attr_val)
                    else:
                        text_val = child.text or ""
                        values_to_test.append(text_val)

            # 编译正则表达式
            try:
                regex = re.compile(pattern, re.IGNORECASE)
            except re.error as e:
                logger.warning("Invalid regex pattern '%s': %s", pattern, e)
                # 正则语法错误时视作不匹配
                if mode == "INCLUDE":
                    return False
                continue

            # 判断是否有任一值匹配该正则
            is_matched = any(regex.search(val) for val in values_to_test)

            if mode == "INCLUDE" and not is_matched:
                return False
            if mode == "EXCLUDE" and is_matched:
                return False

        return True

    @classmethod
    def parse_feed_items(
        cls,
        xml_content: str,
        filter_rules: Optional[List[RssFilterRule]] = None,
        url_extract_rule: Optional[Dict[str, str]] = None,
        return_all: bool = False,
    ) -> Dict[str, Any]:
        """
        解析 RSS/Atom XML 文本，提取频道标题、所有条目及过滤匹配结果。
        若 return_all=True，则返回全部条目并保留各条目的 matched 匹配布尔值。
        """
        root = ET.fromstring(xml_content)
        root_tag = cls._local_tag_name(root.tag).lower()

        channel_title = ""
        items_elements = []

        if root_tag == "rss":
            channel = root.find("channel")
            if channel is not None:
                title_elem = channel.find("title")
                if title_elem is not None:
                    channel_title = (title_elem.text or "").strip()
                items_elements = channel.findall("item")
            else:
                items_elements = root.findall(".//item")
        elif root_tag == "feed":  # Atom 规范
            title_elem = root.find("{http://www.w3.org/2005/Atom}title")
            if title_elem is None:
                title_elem = root.find("title")
            if title_elem is not None:
                channel_title = (title_elem.text or "").strip()
            items_elements = root.findall("{http://www.w3.org/2005/Atom}entry") or root.findall(".//entry")
        else:
            items_elements = root.findall(".//item") or root.findall(".//entry")

        total_count = len(items_elements)
        result_items: List[RssItemPreview] = []
        rules = filter_rules or []
        matched_count = 0

        for item in items_elements:
            # 提取基础字段
            title = ""
            link = ""
            guid = ""
            pub_date = ""
            tag_values = {}

            for child in item:
                ltag = cls._local_tag_name(child.tag).lower()
                text = (child.text or "").strip()
                tag_values[ltag] = text

                if ltag == "title":
                    title = text
                elif ltag == "link":
                    href = child.attrib.get("href")
                    link = href.strip() if href else text
                elif ltag in ["guid", "id"]:
                    guid = text
                elif ltag in ["pubdate", "published", "updated"]:
                    pub_date = text
                elif ltag == "enclosure":
                    tag_values["enclosure@url"] = child.attrib.get("url", "")
                    tag_values["enclosure@type"] = child.attrib.get("type", "")

            # 兜底生成唯一 guid (若无则取 link 或 MD5(title))
            if not guid:
                if link:
                    guid = link
                elif title:
                    guid = hashlib.md5(f"{title}_{pub_date}".encode("utf-8")).hexdigest()
                else:
                    guid = uuid.uuid4().hex

            download_url = cls._extract_download_url(item, url_extract_rule)
            is_matched = cls._evaluate_item_filters(item, rules)
            if is_matched:
                matched_count += 1

            if is_matched or return_all:
                result_items.append(
                    RssItemPreview(
                        guid=guid,
                        title=title or "Untitled",
                        link=link,
                        download_url=download_url,
                        pub_date=pub_date,
                        matched=is_matched,
                        tag_values=tag_values,
                    )
                )

        return {
            "channel_title": channel_title,
            "total_items": total_count,
            "matched_count": matched_count,
            "items": result_items,
        }

    async def preview_feed(
        self,
        feed_url: str,
        filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = None,
        url_extract_rule: Optional[Union[Dict[str, str], str]] = None,
        subtitle_language: Optional[str] = None,
    ) -> Dict[str, Any]:
        """在线预览与测试 RSS 订阅过滤规则"""
        rules = normalize_filter_rules(filter_rules, subtitle_language=subtitle_language)
        extract_rule = normalize_url_extract_rule(url_extract_rule)
        xml_content = await self.fetch_feed_xml(feed_url)
        parsed = self.parse_feed_items(xml_content, rules, extract_rule)
        return {
            "feed_url": feed_url,
            "channel_title": parsed["channel_title"],
            "total_items": parsed["total_items"],
            "matched_count": parsed["matched_count"],
            "items": [item.model_dump() for item in parsed["items"]],
            "filter_rules": [r.model_dump() for r in rules],
            "subtitle_language": subtitle_language,
        }

    async def create_subscription(
        self,
        feed_url: str,
        save_dir: str,
        title: Optional[str] = None,
        filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = None,
        url_extract_rule: Optional[Union[Dict[str, str], str]] = None,
        check_interval_minutes: int = 15,
        download_engine: str = "auto",
        selected_guids: Optional[Union[List[str], List[Any], str]] = None,
        download_existing: bool = True,
        agent_task_id: Optional[str] = None,
        subtitle_language: Optional[str] = None,
    ) -> RssSubscriptionModel:
        """
        创建新的 RSS 订阅任务：
        - 支持存量条目选摘下载（如指定 selected_guids 则仅下载所选项，其余全部标为已处理忽略）
        - 自动进行落地目录白名单校验
        - 若传入 agent_task_id，则在智能体长任务中创建 RSS_TASK 子操作卡片
        - 自动兼容与标准化过滤规则列表/JSON字符串及字幕语言过滤
        """
        valid_dir = validate_sandbox_path(save_dir)
        ensure_nas_compatible_dir(valid_dir)

        norm_rules = normalize_filter_rules(filter_rules, subtitle_language=subtitle_language)
        norm_extract = normalize_url_extract_rule(url_extract_rule)
        norm_guids = normalize_selected_guids(selected_guids)

        # 获取并解析一次 XML，提取频道名称与当前存量条目
        xml_content = await self.fetch_feed_xml(feed_url)
        parsed = self.parse_feed_items(xml_content, norm_rules, norm_extract)

        final_title = title.strip() if title and title.strip() else (parsed["channel_title"] or "RSS 订阅")
        rss_id = f"rss_{uuid.uuid4().hex[:8]}"

        sub = RssSubscriptionModel(
            rss_id=rss_id,
            title=final_title,
            feed_url=feed_url,
            save_dir=valid_dir,
            filter_rules=norm_rules,
            url_extract_rule=norm_extract,
            check_interval_minutes=max(1, check_interval_minutes),
            download_engine=download_engine,
            enabled=True,
            last_checked_at=time.time(),
            agent_task_id=agent_task_id,
            subtitle_language=subtitle_language,
        )

        matched_items: List[RssItemPreview] = parsed["items"]
        all_matched_guids = [it.guid for it in matched_items]

        # 处理存量下载与指纹池记录
        if norm_guids is not None:
            # 用户精确选摘部分条目下载
            selected_set = set(norm_guids)
            for item in matched_items:
                if item.guid in selected_set and item.download_url:
                    self._dispatch_item_download(sub, item)
            # 关键：将所有存量匹配条目均记入已下载指纹库，后续轮询不重复触发
            sub.downloaded_guids = list(set(all_matched_guids))
        elif download_existing:
            # 默认抓取所有当前匹配条目
            for item in matched_items:
                if item.download_url:
                    self._dispatch_item_download(sub, item)
            sub.downloaded_guids = list(set(all_matched_guids))
        else:
            # 仅建立基线，不下载存量
            sub.downloaded_guids = list(set(all_matched_guids))

        self._subscriptions[rss_id] = sub
        self._save_to_disk()

        # 智能体任务联动：写入 sub_action 并自动标记任务完成
        if agent_task_id:
            try:
                agent_task_service.add_sub_action(
                    agent_task_id=agent_task_id,
                    action_type="RSS_TASK",
                    action_id=rss_id,
                    summary=f"RSS订阅: {final_title} ({feed_url[:60]})",
                )
                logger.info("Linked RSS task %s to agent task %s", rss_id, agent_task_id)
                agent_task_service.report_step(
                    agent_task_id=agent_task_id,
                    step_name=f"RSS订阅任务已成功创建并激活: {final_title}",
                    status="COMPLETED",
                    progress=100.0,
                    log_message=f"已成功添加 RSS 订阅源（编号: {rss_id}），保存目录: {valid_dir}，检查周期: {sub.check_interval_minutes} 分钟。",
                )
                agent_task_service.complete_task(
                    agent_task_id=agent_task_id,
                    result={"rss_id": rss_id, "title": final_title, "status": "ACTIVE"},
                    prompt_template=f"请为剧集【{final_title}】创建自动更新的 RSS 订阅任务：源地址为 {feed_url}，保存目录为 {valid_dir}，检查周期为 {sub.check_interval_minutes} 分钟，启用正则过滤并自动下发下载。",
                )
                logger.info("Completed agent task %s upon RSS task creation", agent_task_id)
            except Exception as e:
                logger.warning("Failed to link or complete RSS task in agent task: %s", e)

        return sub

    def _dispatch_item_download(self, sub: RssSubscriptionModel, item: RssItemPreview):
        """派发单条 RSS 资源的下载请求至 DownloaderService"""
        try:
            logger.info("Dispatching RSS download: [%s] %s -> %s", sub.title, item.title, item.download_url)
            res = DownloaderService.dispatch_download(
                url=item.download_url,
                save_dir=sub.save_dir,
                filename=None,
                engine_override=sub.download_engine,
                agent_task_id=sub.agent_task_id,
            )
            record = RssDownloadRecord(
                guid=item.guid,
                title=item.title,
                download_url=item.download_url,
                download_time=time.time(),
                task_id=res.get("task_id"),
                engine=res.get("engine", sub.download_engine),
                status="DISPATCHED",
            )
            sub.download_history.insert(0, record)
            # 仅保留最近 200 条抓取历史
            sub.download_history = sub.download_history[:200]
            sub.total_downloaded_count += 1
            if item.guid not in sub.downloaded_guids:
                sub.downloaded_guids.append(item.guid)

            try:
                from nasio.services.webhook_service import webhook_service
                webhook_service.emit_event(
                    event_type="RSS_MATCHED",
                    summary=f"RSS 订阅命中并派发下载: [{sub.title}] {item.title}",
                    data={
                        "rss_id": sub.rss_id,
                        "subscription_title": sub.title,
                        "item_title": item.title,
                        "save_dir": sub.save_dir,
                        "task_id": res.get("task_id"),
                    },
                    suggested_prompt=f"RSS 订阅 [{sub.title}] 命中新剧集 '{item.title}'，已派发下载至 '{sub.save_dir}' (task_id: {res.get('task_id')})。",
                )
            except Exception as we:
                logger.debug("Failed to emit RSS_MATCHED webhook: %s", we)
        except Exception as e:
            logger.error("Failed to dispatch RSS download for %s: %s", item.title, e)

    async def check_subscription(self, rss_id: str) -> Dict[str, Any]:
        """
        立即执行一次指定 RSS 订阅源的拉取与过滤下载
        """
        sub = self._subscriptions.get(rss_id)
        if not sub:
            raise ValueError(f"RSS Subscription '{rss_id}' not found")

        try:
            xml_content = await self.fetch_feed_xml(sub.feed_url)
            parsed = self.parse_feed_items(xml_content, sub.filter_rules, sub.url_extract_rule)

            downloaded_set = set(sub.downloaded_guids)
            new_dispatched = 0

            for item in parsed["items"]:
                if item.guid not in downloaded_set:
                    if item.download_url:
                        self._dispatch_item_download(sub, item)
                        downloaded_set.add(item.guid)
                        new_dispatched += 1
                    else:
                        # 无法提取有效下载链接但符合规则，也记录已处理避免重复日志
                        downloaded_set.add(item.guid)

            sub.downloaded_guids = list(downloaded_set)
            sub.last_checked_at = time.time()
            sub.last_error = None
            sub.updated_at = time.time()
            self._save_to_disk()

            return {
                "rss_id": rss_id,
                "title": sub.title,
                "status": "SUCCESS",
                "total_feed_items": parsed["total_items"],
                "matched_feed_items": parsed["matched_count"],
                "newly_dispatched": new_dispatched,
            }
        except Exception as e:
            logger.error("Error checking RSS subscription %s: %s", rss_id, e)
            sub.last_error = str(e)
            sub.last_checked_at = time.time()
            self._save_to_disk()
            return {
                "rss_id": rss_id,
                "title": sub.title,
                "status": "FAILED",
                "error": str(e),
                "newly_dispatched": 0,
            }

    def list_subscriptions(self) -> List[RssSubscriptionModel]:
        return list(self._subscriptions.values())

    def get_subscription(self, rss_id: str) -> Optional[RssSubscriptionModel]:
        return self._subscriptions.get(rss_id)

    async def get_subscription_items(self, rss_id: str) -> Dict[str, Any]:
        """获取指定 RSS 订阅当前远端的全部资源列表，并比对下载状态与过滤规则"""
        sub = self.get_subscription(rss_id)
        if not sub:
            raise ValueError(f"RSS Subscription '{rss_id}' not found")

        xml_content = await self.fetch_feed_xml(sub.feed_url)
        parsed = self.parse_feed_items(
            xml_content,
            filter_rules=sub.filter_rules,
            url_extract_rule=sub.url_extract_rule,
            return_all=True,
        )

        downloaded_set = set(sub.downloaded_guids)
        items_with_status = []
        for it in parsed["items"]:
            it.is_downloaded = it.guid in downloaded_set
            items_with_status.append(it)

        return {
            "rss_id": sub.rss_id,
            "title": sub.title,
            "feed_url": sub.feed_url,
            "save_dir": sub.save_dir,
            "download_engine": sub.download_engine,
            "total_items": parsed["total_items"],
            "matched_count": parsed["matched_count"],
            "downloaded_count": sum(1 for it in items_with_status if it.is_downloaded),
            "items": [it.model_dump() for it in items_with_status],
        }

    async def download_selected_items(
        self,
        rss_id: str,
        items: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        """选摘下载指定的条目，派发至下载器并同步计入该订阅的历史与已下载 GUID"""
        sub = self.get_subscription(rss_id)
        if not sub:
            raise ValueError(f"RSS Subscription '{rss_id}' not found")

        dispatched_count = 0
        failed_count = 0
        results = []

        for item_data in items:
            guid = item_data.get("guid", "")
            title = item_data.get("title", "")
            download_url = item_data.get("download_url", "")
            if not download_url:
                failed_count += 1
                results.append({"guid": guid, "title": title, "status": "FAILED", "error": "缺少有效下载链接"})
                continue

            preview_item = RssItemPreview(
                guid=guid,
                title=title or "Untitled",
                link=item_data.get("link", ""),
                download_url=download_url,
                pub_date=item_data.get("pub_date", ""),
                matched=True,
                is_downloaded=True,
            )

            try:
                self._dispatch_item_download(sub, preview_item)
                dispatched_count += 1
                results.append({"guid": guid, "title": title, "status": "DISPATCHED"})
            except Exception as e:
                logger.error("Failed to download selected RSS item %s: %s", title, e)
                failed_count += 1
                results.append({"guid": guid, "title": title, "status": "FAILED", "error": str(e)})

        self._save_to_disk()
        return {
            "rss_id": rss_id,
            "total_requested": len(items),
            "dispatched_count": dispatched_count,
            "failed_count": failed_count,
            "results": results,
            "total_downloaded_count": sub.total_downloaded_count,
        }

    def update_subscription(
        self,
        rss_id: str,
        title: Optional[str] = None,
        save_dir: Optional[str] = None,
        filter_rules: Optional[Union[List[RssFilterRule], List[Dict[str, Any]], List[Any], str]] = None,
        url_extract_rule: Optional[Union[Dict[str, str], str]] = None,
        check_interval_minutes: Optional[int] = None,
        download_engine: Optional[str] = None,
        enabled: Optional[bool] = None,
        subtitle_language: Optional[str] = None,
    ) -> RssSubscriptionModel:
        sub = self._subscriptions.get(rss_id)
        if not sub:
            raise ValueError(f"RSS Subscription '{rss_id}' not found")

        if title is not None:
            sub.title = title
        if save_dir is not None:
            valid_dir = validate_sandbox_path(save_dir)
            ensure_nas_compatible_dir(valid_dir)
            sub.save_dir = valid_dir
        if filter_rules is not None or subtitle_language is not None:
            base_rules = filter_rules if filter_rules is not None else sub.filter_rules
            sub_lang = subtitle_language if subtitle_language is not None else sub.subtitle_language
            sub.filter_rules = normalize_filter_rules(base_rules, subtitle_language=sub_lang)
            if subtitle_language is not None:
                sub.subtitle_language = subtitle_language
        if url_extract_rule is not None:
            sub.url_extract_rule = normalize_url_extract_rule(url_extract_rule)
        if check_interval_minutes is not None:
            sub.check_interval_minutes = max(1, check_interval_minutes)
        if download_engine is not None:
            sub.download_engine = download_engine
        if enabled is not None:
            sub.enabled = enabled

        sub.updated_at = time.time()
        self._save_to_disk()
        return sub

    def delete_subscription(self, rss_id: str) -> bool:
        if rss_id in self._subscriptions:
            del self._subscriptions[rss_id]
            self._save_to_disk()
            return True
        return False

    def toggle_subscription(self, rss_id: str) -> bool:
        sub = self._subscriptions.get(rss_id)
        if not sub:
            raise ValueError(f"RSS Subscription '{rss_id}' not found")
        sub.enabled = not sub.enabled
        sub.updated_at = time.time()
        self._save_to_disk()
        return sub.enabled

    # -------------------------------------------------------------
    # 后台定时轮询调度器协程
    # -------------------------------------------------------------
    def start_scheduler(self):
        """启动后台定时扫描工作协程"""
        if self._polling_task is None or self._polling_task.done():
            self._polling_task = asyncio.create_task(self._scheduler_loop())
            logger.info("RSS Subscription background scheduler started.")

    def stop_scheduler(self):
        if self._polling_task and not self._polling_task.done():
            self._polling_task.cancel()
            logger.info("RSS Subscription background scheduler stopped.")

    async def _scheduler_loop(self):
        logger.info("RSS polling loop active.")
        while True:
            try:
                await asyncio.sleep(60)  # 每 60 秒巡检一次任务到期情况
                now = time.time()
                for sub in list(self._subscriptions.values()):
                    if not sub.enabled:
                        continue
                    interval_sec = sub.check_interval_minutes * 60
                    if now - sub.last_checked_at >= interval_sec:
                        logger.info("Auto-polling RSS feed: [%s] %s", sub.title, sub.feed_url)
                        await self.check_subscription(sub.rss_id)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning("Exception in RSS scheduler loop: %s", e)
                await asyncio.sleep(30)


# 全局单例
rss_service = RssService()
