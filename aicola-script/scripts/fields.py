"""Field list shared by convert.py, check.py, serve.py and fill.py.

A "pack" is one folder holding everything that goes into one aicola project,
one plain-text file per field, plus settings.json.
"""
from pathlib import Path
import json

SKILL_DIR = Path(__file__).resolve().parent.parent

# key, file in the pack, where it goes on aicola, character limit
FIELDS = [
    ("title",           "title.txt",           "剧本配置 → 标题",                          200),
    ("script",          "script.md",           "剧本配置 → 剧本正文",                      None),
    ("world",           "world.md",            "剧本快捷设置 → 世界观",                     10000),
    ("art",             "art.md",              "剧本快捷设置 → 整体美术",                   10000),
    ("cast",            "cast.md",             "剧本快捷设置 → 全剧人设（默认留空）",        10000),
    ("style_video",     "style-video.md",      "风格切换 自定义 → 视频通用提示词",           10000),
    ("style_character", "style-character.md",  "风格切换 自定义 → 角色图片通用提示词",       10000),
    ("style_crowd",     "style-crowd.md",      "风格切换 自定义 → 群像角色图片通用提示词",   10000),
    ("style_scene",     "style-scene.md",      "风格切换 自定义 → 场景图片通用提示词",       10000),
    ("style_other",     "style-other.md",      "风格切换 自定义 → 其他对象图片通用提示词",   10000),
    ("polish",          "polish.md",           "用户自定义设置 → 小节润色提示词",            50000),
]

STYLE_KEYS = ["style_video", "style_character", "style_crowd", "style_scene", "style_other"]

# Style-converter markers -> field keys
STYLE_MARKERS = {
    "视频通用提示词": "style_video",
    "角色图片通用提示词": "style_character",
    "群像角色图片通用提示词": "style_crowd",
    "场景图片通用提示词": "style_scene",
    "其他对象图片通用提示词": "style_other",
    "世界观": "world",
    "整体美术": "art",
}

DEFAULT_SETTINGS = {
    # label on aicola -> option text. fill.py sets each one it knows how to set.
    "风格切换": "自定义",
    "小节润色": "开启",
    "小节润色模型": "Seed 2.1 Pro",
    "视频文本来源": "小节润色文本",
    "脑补角色外表描述": "不脑补",
    "小节生视频模型": "Seedance 2.5",
    "小节视频比例": "16:9",
    "小节视频分辨率": "720p",
    "成片语种": "中文（不翻译）",
    "消除字幕": "开启",
    "角色图片版式": "完整正背面（默认）",
}


def field_path(pack: Path, key: str) -> Path:
    for k, f, _, _ in FIELDS:
        if k == key:
            return pack / f
    raise KeyError(key)


def read_field(pack: Path, key: str) -> str:
    p = field_path(pack, key)
    return p.read_text(encoding="utf-8") if p.exists() else ""


def load_settings(pack: Path) -> dict:
    p = pack / "settings.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return dict(DEFAULT_SETTINGS)
