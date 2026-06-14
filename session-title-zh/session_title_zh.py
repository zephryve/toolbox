#!/usr/bin/env python3
"""
session_title_zh.py — Claude Code session 标题中文化

原理（已实测验证）：
- session 标题有两种来源：ai-title（AI 自动生成，默认英文，随对话反复重写但 picker 显示其值）
  和 custom-title（用户设定，优先级高于 ai-title）。
- 往 session jsonl 追加一条 custom-title 记录，picker 即显示中文，且 ai-title 再重写也盖不过
  （c11c6a52 实测 ai-title×715 全英文 + custom-title×715 中文，显示中文）。
- 所以本工具只做一件事：给「有英文 ai-title 但无 custom-title」的 session 追加中文 custom-title。
  幂等——已有 custom-title 的跳过，每个 session 只中文化一次，写入即锁定、永不再变。

用法：
    python3 session_title_zh.py --scan              # 只扫描统计 + 列待转（不写任何文件）
    python3 session_title_zh.py --apply             # 翻译并写入（自动备份 + 幂等）
    python3 session_title_zh.py --apply --project X # 只处理某个 project 目录
    python3 session_title_zh.py --hook              # SessionEnd/Stop hook 模式：只处理 $CLAUDE_SESSION 当前 session

安全：写入前整目录备份到 ~/.claude/.session-title-backups/{时间戳}/；只追加 custom-title 行，
     绝不改动原有任何行；幂等可重复跑。
"""

import json
import os
import re
import sys
import subprocess
import shutil
from pathlib import Path

PROJECTS_DIR = Path.home() / ".claude" / "projects"
BACKUP_ROOT = Path.home() / ".claude" / ".session-title-backups"


def is_english(s: str) -> bool:
    """标题是否纯英文（无中文字符）——只转英文标题，中文 ai-title 已经满足需求不动。"""
    if not s:
        return False
    return not re.search(r"[一-鿿]", s)


def scan_session(jsonl: Path):
    """返回 (ai_title, has_custom, session_id)。读全文取最后一条 ai-title / 是否有 custom-title。"""
    ai_title = None
    has_custom = False
    sid = jsonl.stem
    try:
        for line in jsonl.open(encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            try:
                j = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = j.get("type")
            if t == "ai-title":
                ai_title = j.get("aiTitle", "")
            elif t == "custom-title":
                has_custom = True
    except (OSError, UnicodeDecodeError):
        pass
    return ai_title, has_custom, sid


def collect(project_filter=None):
    """收集所有待转 session：有英文 ai-title 且无 custom-title。"""
    todo = []      # [(jsonl_path, ai_title, sid)]
    skip_custom = 0
    skip_chinese = 0
    skip_notitle = 0
    proj_dirs = [PROJECTS_DIR] if not PROJECTS_DIR.exists() else sorted(PROJECTS_DIR.iterdir())
    for proj in proj_dirs:
        if not proj.is_dir():
            continue
        if project_filter and project_filter not in proj.name:
            continue
        for jsonl in proj.glob("*.jsonl"):
            ai, has_custom, sid = scan_session(jsonl)
            if has_custom:
                skip_custom += 1
            elif not ai:
                skip_notitle += 1
            elif not is_english(ai):
                skip_chinese += 1
            else:
                todo.append((jsonl, ai, sid))
    return todo, dict(has_custom=skip_custom, chinese=skip_chinese, no_title=skip_notitle)


def translate_batch(titles):
    """调 claude -p 把一批英文标题翻成简洁中文。返回 {英文: 中文}。失败返回空（调用方降级跳过）。"""
    if not titles:
        return {}
    numbered = "\n".join(f"{i+1}. {t}" for i, t in enumerate(titles))
    prompt = (
        "把下面这些 Claude Code 会话标题翻译成简洁、准确的中文（每条 ≤14 字，保留专有名词如 "
        "Claude/visa/QS 等不译）。只输出译文，每行一条，格式 `序号. 中文`，不要任何解释：\n\n" + numbered
    )
    try:
        r = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True, text=True, timeout=120,
        )
        out = r.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}
    mapping = {}
    for line in out.splitlines():
        m = re.match(r"\s*(\d+)[.、)]\s*(.+)", line.strip())
        if m:
            idx = int(m.group(1)) - 1
            if 0 <= idx < len(titles):
                mapping[titles[idx]] = m.group(2).strip()
    return mapping


def append_custom_title(jsonl: Path, sid: str, zh_title: str):
    """只追加一行 custom-title，不动原有内容。"""
    rec = {"type": "custom-title", "customTitle": zh_title, "sessionId": sid}
    with jsonl.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def backup(jsonls, stamp):
    dest = BACKUP_ROOT / stamp
    dest.mkdir(parents=True, exist_ok=True)
    for j in jsonls:
        shutil.copy2(j, dest / j.name)
    return dest


def cmd_scan(project_filter=None):
    todo, skips = collect(project_filter)
    print(f"=== Claude Code session 标题扫描 ===")
    print(f"待中文化（英文 ai-title 且无 custom-title）：{len(todo)}")
    print(f"跳过 · 已有 custom-title（已锁定）：{skips['has_custom']}")
    print(f"跳过 · ai-title 已是中文：{skips['chinese']}")
    print(f"跳过 · 无 ai-title：{skips['no_title']}")
    print()
    if todo:
        print(f"待转列表（前 40 条）：")
        for jsonl, ai, sid in todo[:40]:
            print(f"  {ai}")
        if len(todo) > 40:
            print(f"  …还有 {len(todo) - 40} 条")
    return todo


def cmd_apply(project_filter=None, stamp="manual"):
    todo, _ = collect(project_filter)
    if not todo:
        print("无待转 session（全部已锁定或已中文）。")
        return
    print(f"待转 {len(todo)} 条，备份中…")
    dest = backup([t[0] for t in todo], stamp)
    print(f"已备份 → {dest}")
    # 分批翻译（每批 ≤25 条，控 claude -p 单次负载）
    titles = [ai for _, ai, _ in todo]
    mapping = {}
    for i in range(0, len(titles), 25):
        batch = titles[i:i+25]
        print(f"翻译 {i+1}-{i+len(batch)}/{len(titles)}…")
        mapping.update(translate_batch(batch))
    written = 0
    for jsonl, ai, sid in todo:
        zh = mapping.get(ai)
        if not zh:
            print(f"  跳过（翻译缺失）：{ai}")
            continue
        append_custom_title(jsonl, sid, zh)
        written += 1
        print(f"  ✓ {ai}  →  {zh}")
    print(f"\n完成：{written}/{len(todo)} 写入 custom-title。备份在 {dest}（picker 异常可整目录还原）。")


def cmd_hook():
    """hook 模式：只处理当前 session（$CLAUDE_SESSION_ID / stdin 给的 session_id）。幂等。"""
    sid = os.environ.get("CLAUDE_SESSION_ID", "")
    if not sid:
        try:
            data = json.load(sys.stdin)
            sid = data.get("session_id", "")
        except Exception:
            pass
    if not sid:
        return
    for proj in PROJECTS_DIR.iterdir():
        jsonl = proj / f"{sid}.jsonl"
        if jsonl.exists():
            ai, has_custom, _ = scan_session(jsonl)
            if ai and not has_custom and is_english(ai):
                m = translate_batch([ai])
                zh = m.get(ai)
                if zh:
                    append_custom_title(jsonl, sid, zh)
            return


if __name__ == "__main__":
    args = sys.argv[1:]
    pf = None
    if "--project" in args:
        pf = args[args.index("--project") + 1]
    if "--hook" in args:
        cmd_hook()
    elif "--apply" in args:
        cmd_apply(pf)
    else:
        cmd_scan(pf)
