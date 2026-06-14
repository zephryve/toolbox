# Claude Code Session 标题中文化

把 Claude Code session picker / `/resume` 列表里那些**英文自动标题**变成中文，且**设一次就锁死、永不随对话改动而变**。

---

## 解决什么问题

中文用户（首条消息、对话全程都是中文）在 session 列表里看到的标题大多是英文：

```
Plan Zephryve Engine architecture and workflow      ← 想要：规划 Zephryve 飞轮架构
Scrape Alibaba job listings from career site        ← 想要：抓取阿里招聘岗位
Design scoring system for job evaluation results     ← 想要：岗位评估打分系统设计
```

而且就算手动改了名，还担心"它会不会因为对话又更新了、标题又变回英文"。

---

## 机制原理（全部实测验证，非推断）

Claude Code 的 session jsonl 里有**两种**标题记录：

| 记录类型 | 字段 | 谁生成 | 语言 | 行为 |
|---------|------|--------|------|------|
| `ai-title` | `aiTitle` | Claude Code 自动 | **默认英文**（内部 prompt 英文，与对话语言无关）| 随对话**反复重写**（实测一个 session 写了 **715 次**）|
| `custom-title` | `customTitle` | 用户设定（GUI 改名 / 本工具）| 你定 | 写入即锁定 |

**两个关键实测结论**：

1. **ai-title 默认英文，跟你说什么语言无关**——抽样 8 个 session，首条消息 100% 中文，aiTitle 100% 英文；全库搜"中文 aiTitle"零命中。`settings.json` 的 `language` 配置项只管「Claude 回复语言 / 语音听写」，**不管 session 标题**（官方文档确认，无任何标题语言配置项）。

2. **custom-title 压 ai-title，写一次就锁死**——铁证：session `c11c6a52` 有 `ai-title × 715`（英文 "Web scraping CRS organization"）+ `custom-title × 715`（中文"抓取CRS中外合作办学网页"），**picker 显示的是中文**。ai-title 重写 715 次都盖不过 custom-title。

3. **外部写入 picker 认**——实测：往一个已关闭 session（`0fc67be7`，原标题 "Update Claude CLI"）的 jsonl 追加一条 custom-title `"升级 Claude CLI"`，刷新 picker → 标题变中文 ✅。

**所以「自动 + 不老变」天然成立**：往 jsonl 追加一条中文 `custom-title` 记录，picker 即显示中文；它优先级高于 ai-title，无论 ai-title 后续怎么重写都盖不过 → 设一次永不变。

---

## 这个工具做什么

只做一件事：给「有英文 ai-title 但还没有 custom-title」的 session **追加**一条中文 custom-title。

- **幂等**：已有 custom-title 的 session 跳过——每个标题只中文化一次，写入即锁定，重复跑无副作用。
- **只追加不改原内容**：往 jsonl 末尾加一行，绝不动原有任何行。
- **写前整目录备份**：备份到 `~/.claude/.session-title-backups/{时间戳}/`，picker 异常可整目录还原。

## 用法

```bash
# 1. 只扫描统计 + 列待转（不写任何文件）
python3 session_title_zh.py --scan
python3 session_title_zh.py --scan --project zephryve-engine   # 只看某个项目

# 2. 翻译并写入（自动备份 + 幂等）—— 调 claude -p 批量翻译英文标题
python3 session_title_zh.py --apply
python3 session_title_zh.py --apply --project zephryve-engine

# 3. hook 模式：只处理当前 session（挂 SessionEnd hook 用，见下）
python3 session_title_zh.py --hook
```

## 增量自动（新 session 也中文化）

挂 **SessionEnd** hook（不是 Stop）——session 结束时标题已生成、session 已关闭，写 custom-title 不会被 Claude Code 内存状态覆盖（跟实验的已关闭 session 同场景）：

```jsonc
// ~/.claude/settings.json
{
  "hooks": {
    "SessionEnd": [
      { "hooks": [ {
        "type": "command",
        "command": "python3 ~/zephryve/toolbox/session-title-zh/session_title_zh.py --hook",
        "timeout": 130
      } ] }
    ]
  }
}
```

幂等保证：hook 每次只在「当前 session 有英文 ai-title 且无 custom-title」时翻译一次，写入后再触发就跳过 → 永不重复变。

## 局限 / 注意

- **活跃 session 不要用 Stop hook 写**：custom-title 是 Claude Code 内部维护的状态（每次保存同步重写），对正活着的 session 从外部写，可能被下次保存覆盖。所以增量只用 **SessionEnd**（已关闭场景，实测安全），存量批量也只处理已关闭 session。
- **翻译靠 `claude -p`**：需要 `claude` CLI 可用；翻译质量取决于模型，专有名词（Claude/visa/QS）保留不译已在 prompt 约束。
- **官方若日后支持标题语言配置**（GitHub issue #48778 状态混乱、官方文档暂无），本工具即可退役。

## 当前规模（zephryve-engine 项目，2026-06-14 实测）

- 待中文化：**22**（英文 ai-title 无 custom-title）
- 已锁定：4（此前手动改的中文标题）
- eval 空壳无标题：187（不处理）
