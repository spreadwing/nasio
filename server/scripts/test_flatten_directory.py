import os
import sys
import shutil
import tempfile
import unittest

# 将 src 加入 sys.path 以便直接导入
SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

from nasio.core.config import get_app_config
from nasio.services.file_service import FileGovernanceService
from nasio.services.trash_service import TrashService


class TestFlattenDirectory(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test_base = os.path.realpath(tempfile.mkdtemp(prefix="nas_test_flatten_"))
        cls.trash_dir = os.path.join(cls.test_base, ".trash")
        os.makedirs(cls.trash_dir, exist_ok=True)

        # 临时将测试目录注入配置允许的白名单
        cfg = get_app_config()
        cfg.storage.allowed_paths.append(cls.test_base)
        cfg.trash.trash_dir = cls.trash_dir

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.test_base, ignore_errors=True)

    def test_01_dry_run(self):
        """测试 1: 验证 dry_run 模式仅输出计划，不实际变动磁盘"""
        work_dir = os.path.join(self.test_base, "dry_run_show")
        ep01 = os.path.join(work_dir, "Ep01")
        ep02 = os.path.join(work_dir, "Ep02")
        os.makedirs(ep01, exist_ok=True)
        os.makedirs(ep02, exist_ok=True)

        # 创建测试文件
        with open(os.path.join(ep01, "Ep01.mkv"), "w") as f:
            f.write("video content 01")
        with open(os.path.join(ep01, "Ep01.ass"), "w") as f:
            f.write("subtitle content 01")
        with open(os.path.join(ep01, "Fonts.7z"), "w") as f:
            f.write("shared font pack data")

        with open(os.path.join(ep02, "Ep02.mkv"), "w") as f:
            f.write("video content 02")
        with open(os.path.join(ep02, "Fonts.7z"), "w") as f:
            f.write("shared font pack data")
        with open(os.path.join(ep02, ".DS_Store"), "w") as f:
            f.write("mac junk")

        res = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            dry_run=True,
        )

        self.assertTrue(res["dry_run"])
        self.assertEqual(res["total_moved"], 4)  # Ep01.mkv, Ep01.ass, Fonts.7z, Ep02.mkv
        self.assertEqual(res["total_deduped"], 1)  # Ep02/Fonts.7z
        self.assertEqual(res["total_dirs_removed"], 2)  # Ep01, Ep02

        # 磁盘原状态检验：所有文件及子目录依旧保持原位
        self.assertTrue(os.path.exists(os.path.join(ep01, "Ep01.mkv")))
        self.assertTrue(os.path.exists(os.path.join(ep02, "Fonts.7z")))
        self.assertFalse(os.path.exists(os.path.join(work_dir, "Ep01.mkv")))

    def test_02_inplace_flatten_and_dedup(self):
        """测试 2: 真实原地扁平化、相同哈希伴随文件移至回收站、空目录软删除"""
        work_dir = os.path.join(self.test_base, "inplace_show")
        ep01 = os.path.join(work_dir, "[Sub] Ep01")
        ep02 = os.path.join(work_dir, "[Sub] Ep02")
        ep03 = os.path.join(work_dir, "[Sub] Ep03")
        for p in [ep01, ep02, ep03]:
            os.makedirs(p, exist_ok=True)

        font_data = "FONT_CONTENT_IDENTICAL_12345"
        for i, p in enumerate([ep01, ep02, ep03], 1):
            with open(os.path.join(p, f"Ep0{i}.mkv"), "w") as f:
                f.write(f"video data {i}")
            with open(os.path.join(p, f"Ep0{i}.ass"), "w") as f:
                f.write(f"sub data {i}")
            with open(os.path.join(p, "Fonts.7z"), "w") as f:
                f.write(font_data)

        # 放入 junk 文件
        with open(os.path.join(ep02, ".DS_Store"), "w") as f:
            f.write("junk")

        res = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            dry_run=False,
            remove_empty_dirs=True,
            dedup_companions=True,
        )

        self.assertFalse(res["dry_run"])
        # 验证根目录存在各集视频、字幕与且仅有一份 Fonts.7z
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep01.mkv")))
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep01.ass")))
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep02.mkv")))
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep03.mkv")))
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Fonts.7z")))
        self.assertFalse(os.path.exists(os.path.join(work_dir, "Fonts_1.7z")))

        # 验证重复 Fonts.7z 计数为 2
        self.assertEqual(res["total_deduped"], 2)

        # 验证单集子目录均已软删除（不在原位置）
        self.assertFalse(os.path.exists(ep01))
        self.assertFalse(os.path.exists(ep02))
        self.assertFalse(os.path.exists(ep03))

    def test_03_differing_companions_and_fonts_dir(self):
        """测试 3: 伴随文件哈希不同自动改名保留，解压版 Fonts 目录归并"""
        work_dir = os.path.join(self.test_base, "fonts_show")
        ep01 = os.path.join(work_dir, "Ep01")
        ep02 = os.path.join(work_dir, "Ep02")
        ep03_fonts = os.path.join(work_dir, "Ep03", "Fonts")
        os.makedirs(ep01, exist_ok=True)
        os.makedirs(ep02, exist_ok=True)
        os.makedirs(ep03_fonts, exist_ok=True)

        with open(os.path.join(ep01, "Ep01.mkv"), "w") as f:
            f.write("v1")
        with open(os.path.join(ep01, "Fonts.7z"), "w") as f:
            f.write("FONT_VERSION_1")

        with open(os.path.join(ep02, "Ep02.mkv"), "w") as f:
            f.write("v2")
        with open(os.path.join(ep02, "Fonts.7z"), "w") as f:
            f.write("FONT_VERSION_2_DIFFERENT")

        with open(os.path.join(ep03_fonts, "CustomFont.otf"), "w") as f:
            f.write("OTF_DATA")

        res = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            dry_run=False,
            dedup_companions=True,
        )

        # 验证两个不同内容的 Fonts.7z 都被保留（Fonts.7z 与 Fonts_1.7z）
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Fonts.7z")))
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Fonts_1.7z")))

        # 验证解压形态的字体文件归入根目录 Fonts/ 下
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Fonts", "CustomFont.otf")))

    def test_04_cross_directory_flatten(self):
        """测试 4: 跨目录提取 target_dir != source_dir"""
        src_dir = os.path.join(self.test_base, "cross_src")
        dst_dir = os.path.join(self.test_base, "cross_dst")
        sub = os.path.join(src_dir, "Subfolder")
        os.makedirs(sub, exist_ok=True)

        with open(os.path.join(sub, "movie.mp4"), "w") as f:
            f.write("movie stream")

        res = FileGovernanceService.flatten_directory(
            source_dir=src_dir,
            target_dir=dst_dir,
            dry_run=False,
        )

        self.assertTrue(os.path.exists(os.path.join(dst_dir, "movie.mp4")))
        self.assertFalse(os.path.exists(os.path.join(sub, "movie.mp4")))

    def test_05_conflict_resolution(self):
        """测试 5: 主媒体冲突策略（rename_suffix 与 skip）"""
        work_dir = os.path.join(self.test_base, "conflict_show")
        sub = os.path.join(work_dir, "Ep01_v2")
        os.makedirs(sub, exist_ok=True)

        # 根目录已有不同内容的同名视频
        with open(os.path.join(work_dir, "Ep01.mkv"), "w") as f:
            f.write("ORIGINAL_CONTENT")
        with open(os.path.join(sub, "Ep01.mkv"), "w") as f:
            f.write("NEW_RE_ENCODE_CONTENT")

        # 1. 默认 rename_suffix
        res = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            conflict_resolution="rename_suffix",
            dry_run=False,
            remove_empty_dirs=False,
        )
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep01_1.mkv")))

        # 2. skip 策略
        sub2 = os.path.join(work_dir, "Ep01_v3")
        os.makedirs(sub2, exist_ok=True)
        with open(os.path.join(sub2, "Ep01.mkv"), "w") as f:
            f.write("THIRD_VERSION")

        res_skip = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            conflict_resolution="skip",
            dry_run=False,
        )
        self.assertEqual(res_skip["total_skipped"], 1)
        self.assertTrue(os.path.exists(os.path.join(sub2, "Ep01.mkv")))

    def test_06_unhandled_files_protection(self):
        """测试 6: 当子目录含有未识别格式的文件时，子目录安全保留不被删除"""
        work_dir = os.path.join(self.test_base, "safety_show")
        sub = os.path.join(work_dir, "Ep01")
        os.makedirs(sub, exist_ok=True)

        with open(os.path.join(sub, "Ep01.mkv"), "w") as f:
            f.write("video")
        # 未知自定义扩展名或文件
        with open(os.path.join(sub, "mystery.unknown_format"), "w") as f:
            f.write("keep me safe")

        res = FileGovernanceService.flatten_directory(
            source_dir=work_dir,
            dry_run=False,
            remove_empty_dirs=True,
        )

        # 视频被提取
        self.assertTrue(os.path.exists(os.path.join(work_dir, "Ep01.mkv")))
        # 子目录因为包含未知文件，被安全保留
        self.assertTrue(os.path.exists(sub))
        self.assertTrue(os.path.exists(os.path.join(sub, "mystery.unknown_format")))
        self.assertTrue(any("retained" in w for w in res["warnings"]))


if __name__ == "__main__":
    unittest.main()
