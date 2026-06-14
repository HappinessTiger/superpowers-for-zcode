# Tests

测试脚本用于验证 install / uninstall 的行为，**不会**修改你真实的 `~/.agents/` 或 `~/AGENTS.md`。

## 策略

测试通过重定向 `HOME` 环境变量到一个临时目录，让 install/uninstall 脚本在隔离环境里运行。测试结束后清理临时目录。

## 覆盖的场景

| # | 场景 | Windows | Unix | 备注 |
|---|------|---------|------|------|
| T1 | 干净环境安装 | ✅ | ✅ | 核心路径 |
| T2 | 重复安装被拦截 | ✅ | ✅ | manifest 检测 |
| T6 | 干净卸载 | ✅ | ✅ | manifest 回滚 |
| T7 | AGENTS.md 被改过 | ✅ (Force) | ✅ (--force) | hash 保护 |
| T8 | 未安装时卸载 | ✅ | ✅ | 无副作用 |
| T3 | 无 git 环境 | manual | manual | 需模拟，标记 manual |
| T4 | 网络不可达 | manual | manual | 需断网，标记 manual |
| T5 | 安装中途失败 | manual | manual | 需篡改上游，标记 manual |
| T9 | 跨平台一致性 | — | — | 由两套脚本分别保证 |

`manual` 的场景需要人工干预环境，不在自动化脚本里跑。

## 运行

### Windows（PowerShell）

```powershell
cd D:\workShop\githubProjects\superpowersforzcode
.\tests\test.ps1
```

### macOS / Linux

```bash
cd /path/to/superpowers-for-zcode
./tests/test.sh
```

测试输出会标明每个场景 PASS/FAIL，并在末尾汇总。退出码：0 = 全过，非 0 = 有失败。

## 前置要求

测试需要联网（T1 会真的 git clone 上游 obra/superpowers）。
