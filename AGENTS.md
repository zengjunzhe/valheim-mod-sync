# AGENTS.md — 给 AI 助手的操作说明

这个项目让两台机器（macOS / Windows）上的《英灵神殿》（Valheim）mod 保持完全一致。
任何 AI 助手（Cindy / Claude Code / Codex 等）在这台机器上处理「装 mod、同步 mod、联机进不去」时，按本文执行。

## 你在哪一边

- **Windows（对象）**：`C:\valheim-mod-sync`，本地没有 Git 也正常。
- **macOS（用户）**：`~/valheim-mod-sync`，同时也是清单的维护方。

先确认当前目录里有 `mods.json` 和 `scripts/`，没有就说明还没下载脚本包：
`https://qinminbao.com/valheim/valheim-mod-sync.zip`

## 硬性规则

1. 只按 `mods.json` 同步，**不要手动往 `BepInEx/plugins` 里放任何文件**。
2. **不要修改** `mods.json` 里的版本号或 SHA256。清单只由 Mac 侧维护并发布。
3. 同步前 **必须关闭 Valheim**；脚本会自己检查并报错。
4. 用户要求「加一个 mod」时：不要自己装。告诉用户清单由另一台机器发布，需要对方执行 `add-mod` + `deploy`。
5. 用户要求「删一个 mod」时：也不要手动删 `BepInEx/plugins` 里的文件夹——下次同步会把它装回来。正确做法是等 Mac 侧更新清单，下次同步会自动把它移到 `BepInEx/plugins-disabled/`。
6. 失败时保留原始报错，不要猜、不要跳过哈希校验。

## Windows 同步

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\valheim-mod-sync\scripts\sync.ps1
```

预期：退出码 0，最后一行类似

```
Done: 0 installed/updated, 9 up to date, 0 disabled.
```

验证是否真的加载了：

1. 读 `C:\Program Files (x86)\Steam\steamapps\common\Valheim\BepInEx\LogOutput.log`
   （无 Steam 默认路径时用脚本自动检测的结果）。
2. 找 `Loading [` 开头的行，逐条对比期望状态：
   `https://qinminbao.com/valheim/SYNC-STATUS.md`

> `scripts\play.bat` 是给人双击用的，失败会 `pause` 等回车；自动化请直接调用上面的 PowerShell 命令。

## macOS 同步

```bash
bash ~/valheim-mod-sync/scripts/sync.sh
```

验证加载：

```bash
bash ~/valheim-mod-sync/scripts/check.sh
```

它读取 `BepInEx/LogOutput.log`，逐条对比清单并给出 ✓/✗；日志缺失说明这次启动没走 `play.sh`。

## 什么时候同步

- 每次启动游戏前（`play.sh` / `play.bat` 已内置）。
- 用户说「进不去对方房间 / 进去就掉线 / 看不到对方的东西」时，先跑一次同步再判断。

## 协作：怎么把问题推回来

仓库地址就是唯一入口：`https://github.com/zengjunzhe/valheim-mod-sync`

她的 Windows 机器要能 `git push`，需要两件事：装 Git + 被加为仓库协作者（Mac 侧在仓库 Settings → Collaborators 里加）。已经有克隆目录的话：

```bash
git pull --rebase
```

改完脚本或写完报告：

```bash
git add -A
git commit -m "report: 2026-11-16 windows sync failed"
git push
```

推完告诉用户「已推送」，Mac 侧会 `git pull` 看到。

- **可以改**：`scripts/`、`README.md`、`AGENTS.md`、`reports/`
- **不要改**：`mods.json` 里的 `version` / `sha256`（清单由 Mac 侧发布，改了会让两台机器对不上）
- **不要跑** `scripts/deploy-mirror.sh`（它需要 SSH 到京东云，是 Mac 侧的活）

### 报告写到哪

`reports/YYYY-MM-DD-windows.md`，模板见 `reports/TEMPLATE.md`。内容只要四样：现象、执行的命令、原始输出、结论/需要对方做什么。

还没有 push 权限时：把同样的内容发给用户转达，不要卡在那里反复重试。

## 常见错误对照

| 报错 | 含义 | 处理 |
| --- | --- | --- |
| `Failed to fetch manifest` / `拉取清单失败` | 服务器和 GitHub 都不通 | 检查网络后重试；仍失败报告原始报错 |
| `SHA256 mismatch` / `哈希不匹配` | 上游重新打包或文件损坏 | 重试一次；仍失败报告 URL 与两个哈希 |
| `Close Valheim before syncing` / `正在运行` | 游戏没退 | 关闭游戏后重跑 |
| `Valheim not found` | Steam 库路径非默认 | `-ValheimDir 'D:\Steam\steamapps\common\Valheim'`（Mac 用 `VALHEIM_DIR=...`） |
| 日志里没有 `Loading [` 行 | BepInEx 没生效 | 确认游戏目录有 `BepInEx/core/BepInEx.Preloader.dll`；Windows 重跑同步，Mac 检查 Steam 启动项 |

## 回报格式

给用户三行以内：

1. 结论（同步成功 / 失败在哪一步）
2. 关键输出（`Done:` 行或错误原文）
3. 需要对方做什么（通常：让 Mac 侧重新发布一次）

## 不要做的事

- 不要用 r2modman / Vortex 管理这台机器的 mod，会和本方案抢同一份 `BepInEx`。
- 不要在游戏运行时同步。
- 不要把 `BepInEx/plugins-disabled` 里的东西手动搬回来；那是清单移除后的备份。
- 不要为了「让游戏先能进」而临时删别人的 mod：版本不一致会直接连不上，应该等清单对齐。
- 不要用「不运行 play.bat」当作回原版：Windows 上 BepInEx 通过游戏目录里的 `winhttp.dll` 自动注入，必须把它改名或移走才真正不加载 mod。
