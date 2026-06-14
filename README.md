# Superpowers for ZCode

> 一行命令，让 [ZCode](https://z.ai) 用上 [Superpowers](https://github.com/obra/superpowers) 的 14 个开发方法论技能（TDD、系统化调试、头脑风暴、代码评审……）。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 这是什么？

[Superpowers](https://github.com/obra/superpowers) 是一套给 AI 编码智能体用的开发方法论，以一组可组合的 Skill 构成，能让 Agent 在干活时自动遵守 TDD、先头脑风暴再写代码、系统化调试等纪律。官方支持 Claude Code / Codex / Cursor 等平台。

本仓库是 **Superpowers 的 ZCode 适配安装器**。由于 ZCode 的插件市场目前不开放第三方签名，本项目采用"用户态安装"方式：把 Superpowers 的 skills 复制到 ZCode 会扫描的 `~/.agents/skills/` 目录，并生成一个 bootstrap 文件 `AGENTS.md`。

**已验证**：ZCode 会扫描 `~/.agents/skills/` 目录，Superpowers 的 SKILL.md 格式与 ZCode 完全兼容，无需内容改写。

## 前置要求

- 已安装 [ZCode](https://z.ai)
- 已安装 [git](https://git-scm.com/)（安装时需要联网 clone 上游）

## 快速开始

### Windows（PowerShell）

```powershell
git clone https://github.com/<你的fork>/superpowers-for-zcode.git
cd superpowers-for-zcode
.\install.ps1
```

### macOS / Linux（Bash）

```bash
git clone https://github.com/<你的fork>/superpowers-for-zcode.git
cd superpowers-for-zcode
./install.sh
```

安装完成后**重启 ZCode**（开新会话），即可看到 14 个技能出现在可用技能列表。

## 验证安装

重启 ZCode 后，新会话里说一句：

> 帮我设计一个 XXX 功能

应该会看到 ZCode 主动触发 `brainstorming` 技能（或在系统提示的可用技能列表里看到它）。也可以直接用 `/brainstorming` 显式调用。

## 卸载

### Windows

```powershell
.\uninstall.ps1           # 交互式（AGENTS.md 被改过会问）
.\uninstall.ps1 -Force    # 强制，不问
```

### macOS / Linux

```bash
./uninstall.sh            # 交互式
./uninstall.sh --force    # 强制
```

卸载会：① 按安装清单精确删除 14 个技能；② 删除 `AGENTS.md`（如果你改过会提示确认）；③ 删除 manifest。**不会动你 `~/.agents/skills/` 里的其他技能**。

## 工作原理

```
install 脚本：
  1. 前置检查（git 可用、未重复安装）
  2. git clone --depth 1 --branch <VERSION> 上游 obra/superpowers 到临时目录
  3. 复制 skills/* → ~/.agents/skills/
  4. 渲染 templates/AGENTS.md.template → ~/AGENTS.md（占位符替换）
  5. 写 manifest（~/.agents/.superpowers-for-zcode.manifest.json）
  6. 清理临时目录
```

`VERSION` 文件 pin 住上游 tag（当前 `v5.1.0`），保证可复现。manifest 记录全部安装细节，卸载时精确回滚。

## FAQ

**Q: 为什么不是一个 ZCode 插件？**
A: ZCode 插件市场目前对第三方插件做 hash 签名校验，非官方渠道分发的插件无法被加载（已实测验证）。本项目的"用户态安装"方式绕开了这个限制，直接把 skills 放到 ZCode 会扫描的目录。

**Q: `AGENTS.md` 是什么？会被 ZCode 读取吗？**
A: `AGENTS.md` 是给 ZCode 看的 bootstrap 指令文件，放在用户主目录。Superpowers 在 Claude Code 上靠 SessionStart Hook 自动注入方法论，ZCode 没有等价 hook，所以用这个静态文件替代。已验证会被 ZCode 读取生效。

**Q: 我想把 AGENTS.md 放到别处怎么办？**
A: 设置环境变量 `SP4Z_AGENTS_MD_PATH`，例如：
```bash
# Windows
$env:SP4Z_AGENTS_MD_PATH = "$env:USERPROFILE\.zcode\AGENTS.md"; .\install.ps1
# Unix
SP4Z_AGENTS_MD_PATH="$HOME/.zcode/AGENTS.md" ./install.sh
```

**Q: 如何更新到 Superpowers 新版本？**
A: 先 `uninstall`，再修改本仓库的 `VERSION` 文件为新 tag，再 `install`。

**Q: 安全吗？**
A: 全程只 clone 上游公开仓库 + 复制 markdown 文件到你的 `~/.agents/`，不修改任何 ZCode 配置，不碰系统目录，可一键卸载。脚本是纯文本可审计。

## 致谢

- 上游项目：[obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent（MIT）
- 本项目仅在 ZCode 平台做安装适配，所有方法论内容版权归原作者

## 许可证

[MIT](LICENSE) — 本仓库及上游 obra/superpowers 均为 MIT。
