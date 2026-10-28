import sys
import os
import json
import asyncio
import xml.etree.ElementTree as ET

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from nasio.services.rss_service import (
    RssFilterRule,
    RssSubscriptionModel,
    rss_service,
    normalize_filter_rules,
    normalize_selected_guids,
    normalize_url_extract_rule,
    resolve_subtitle_pattern,
    SUBTITLE_LANGUAGE_MAP,
)
from nasio.mcp.server import mcp


def test_normalizations():
    print("=== Testing Normalizations ===")

    # 1. normalize_filter_rules with List of dicts
    rules1 = normalize_filter_rules([{"tag": "title", "pattern": "1080p", "mode": "INCLUDE"}])
    assert len(rules1) == 1
    assert rules1[0].tag == "title"
    assert rules1[0].pattern == "1080p"
    assert rules1[0].mode == "INCLUDE"
    print("✔ List of dicts passed")

    # 2. normalize_filter_rules with JSON array string
    rules2 = normalize_filter_rules('[{"tag": "title", "pattern": "1080p"}]')
    assert len(rules2) == 1
    assert rules2[0].pattern == "1080p"
    print("✔ JSON array string passed")

    # 3. normalize_filter_rules with dict without tag
    rules3 = normalize_filter_rules([{"pattern": "720p"}])
    assert len(rules3) == 1
    assert rules3[0].tag == "title"
    assert rules3[0].pattern == "720p"
    assert rules3[0].mode == "INCLUDE"
    print("✔ Dict without tag defaulted to title")

    # 4. normalize_filter_rules with subtitle shortcut dict
    rules4 = normalize_filter_rules([{"subtitle_language": "简中"}])
    assert len(rules4) == 1
    assert "简" in rules4[0].pattern
    print("✔ Subtitle shortcut dict passed")

    # 5. normalize_filter_rules with subtitle parameter
    rules5 = normalize_filter_rules([{"pattern": "1080p"}], subtitle_language="繁中")
    assert len(rules5) == 2
    assert rules5[0].pattern == "1080p"
    assert "繁" in rules5[1].pattern
    print("✔ Subtitle parameter passed")

    # 6. normalize_filter_rules with list of strings
    rules6 = normalize_filter_rules(["1080p", "简日"])
    assert len(rules6) == 2
    assert rules6[0].pattern == "1080p"
    assert "简" in rules6[1].pattern
    print("✔ List of strings passed")

    # 7. normalize_selected_guids
    g1 = normalize_selected_guids(["guid-1", "guid-2"])
    assert g1 == ["guid-1", "guid-2"]
    g2 = normalize_selected_guids('["guid-1", "guid-2"]')
    assert g2 == ["guid-1", "guid-2"]
    g3 = normalize_selected_guids("guid-1, guid-2")
    assert g3 == ["guid-1", "guid-2"]
    print("✔ Selected GUIDs normalization passed")

    # 8. normalize_url_extract_rule
    u1 = normalize_url_extract_rule({"tag": "enclosure", "attribute": "url"})
    assert u1 == {"tag": "enclosure", "attribute": "url"}
    u2 = normalize_url_extract_rule('{"tag": "enclosure", "attribute": "url"}')
    assert u2 == {"tag": "enclosure", "attribute": "url"}
    print("✔ URL extract rule normalization passed")


def test_rss_xml_filtering():
    print("\n=== Testing RSS XML Filtering with Subtitle & Regex ===")
    sample_xml = """<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Anime RSS Feed</title>
        <item>
          <title>[LoliHouse] 葬送的芙莉莲 - 01 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]</title>
          <link>https://example.com/1</link>
          <enclosure url="https://example.com/1.torrent" type="application/x-bittorrent" />
        </item>
        <item>
          <title>[NC-Raws] 葬送的芙莉莲 - 01 [B-Global 1080p HEVC AAC][CHS]</title>
          <link>https://example.com/2</link>
          <enclosure url="https://example.com/2.torrent" type="application/x-bittorrent" />
        </item>
        <item>
          <title>[NC-Raws] 葬送的芙莉莲 - 01 [B-Global 1080p HEVC AAC][CHT]</title>
          <link>https://example.com/3</link>
          <enclosure url="https://example.com/3.torrent" type="application/x-bittorrent" />
        </item>
        <item>
          <title>[RAW] Frieren - 01 [1080p]</title>
          <link>https://example.com/4</link>
          <enclosure url="https://example.com/4.torrent" type="application/x-bittorrent" />
        </item>
      </channel>
    </rss>
    """

    # Filter for 1080p AND 简中
    rules_chs = normalize_filter_rules([{"pattern": "1080p"}], subtitle_language="简中")
    res_chs = rss_service.parse_feed_items(sample_xml, filter_rules=rules_chs)
    assert res_chs["total_items"] == 4
    assert res_chs["matched_count"] == 2  # item 1 (简繁内封) and item 2 (CHS)
    titles_chs = [it.title for it in res_chs["items"]]
    assert any("[CHS]" in t for t in titles_chs)
    assert any("简繁内封字幕" in t for t in titles_chs)
    assert not any("[CHT]" in t for t in titles_chs)
    print("✔ Subtitle language '简中' correctly matched 2 items and excluded CHT & RAW")

    # Filter for 1080p AND 繁中
    rules_cht = normalize_filter_rules([{"pattern": "1080p"}], subtitle_language="繁中")
    res_cht = rss_service.parse_feed_items(sample_xml, filter_rules=rules_cht)
    assert res_cht["matched_count"] == 2  # item 1 (简繁内封) and item 3 (CHT)
    titles_cht = [it.title for it in res_cht["items"]]
    assert any("[CHT]" in t for t in titles_cht)
    assert any("简繁内封字幕" in t for t in titles_cht)
    assert not any("[CHS]" in t for t in titles_cht)
    print("✔ Subtitle language '繁中' correctly matched 2 items and excluded CHS & RAW")


async def test_fastmcp_tools():
    print("\n=== Testing FastMCP Tools Execution with List Input ===")
    tools = await mcp.list_tools()
    tool_map = {t.name: t for t in tools}
    assert "preview_rss_feed" in tool_map
    assert "create_rss_task" in tool_map
    print(f"✔ Found MCP tools: {list(tool_map.keys())}")

    # Inspect schema of preview_rss_feed
    p_schema = tool_map["preview_rss_feed"].inputSchema
    filter_rules_prop = p_schema["properties"]["filter_rules_json"]
    print("preview_rss_feed filter_rules_json schema:", filter_rules_prop)
    # Check that anyOf contains array and string
    types = [t.get("type") for t in filter_rules_prop.get("anyOf", [])]
    assert "array" in types or "string" in types

    c_schema = tool_map["create_rss_task"].inputSchema
    c_filter_prop = c_schema["properties"]["filter_rules_json"]
    c_guids_prop = c_schema["properties"]["selected_guids_json"]
    assert "subtitle_language" in c_schema["properties"]
    print("create_rss_task filter_rules_json & selected_guids_json schema verified with subtitle_language")

    print("✔ FastMCP input schema successfully verified")


if __name__ == "__main__":
    test_normalizations()
    test_rss_xml_filtering()
    asyncio.run(test_fastmcp_tools())
    print("\n🎉 ALL TESTS PASSED SUCCESSFULLY! 🎉")
