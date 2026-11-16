# Valheim Mod Sync

两个人联机玩 Valheim 时，让两台机器（macOS + Windows）上的 mod **永远保持同一份版本**。

- `mods.json` 是唯一真相：每个 mod 的版本号和 SHA256 都锁死在这里。
- 每次启动游戏前跑一次同步脚本：缺的装上、旧的换掉、清单里没有的移到 `BepInEx/plugins-disabled/`。
- 一个人加 mod，另一个人下次启动就自动跟上，不需要互发压缩包。

> Valheim 没有官方创意工坊，也没有"进服自动下载 mod"的原生机制。这个项目把同步放进**游戏启动流程**：Steam 启动 → 先同步 → 再启动游戏。所以是"下次启动生效"，不是游戏内热更新；如果对方正在游戏里，需要重开一次。

清单和安装包放在自己的京东云服务器上（`https://qinminbao.com/valheim/`），国内直连；服务器不可用时自动退回 GitHub / Thunderstore。

## 目录结构

```
mods.json                    # 共享清单（版本 + SHA256）
scripts/sync.sh              # macOS 同步
scripts/play.sh              # macOS 启动器：同步 + 启动
scripts/add-mod.sh           # 往清单里加/删 mod（自动算哈希）
scripts/deploy-mirror.sh     # 发布清单 + 安装包到京东云
scripts/print_packages.py    # 部署时输出包列表
scripts/sync.ps1             # Windows 同步
scripts/play.bat             # Windows 启动器：同步 + 启动
scripts/validate.py          # 清单校验（CI 也会跑）
```

## 首次设置 · macOS

1. 拿到项目，放在固定位置 `~/valheim-mod-sync`：

   ```bash
   git clone https://github.com/zengjunzhe/valheim-mod-sync.git ~/valheim-mod-sync
   ```

   GitHub 打不开的话，下载 `https://qinminbao.com/valheim/valheim-mod-sync.zip` 解压到同一位置即可。
2. 同步一次（会装 BepInEx 和清单里的全部 mod）：

   ```bash
   bash ~/valheim-mod-sync/scripts/sync.sh
   ```

3. Steam → 右键 Valheim → **属性 → 启动选项**，填：

   ```
   /bin/bash "/Users/你的用户名/valheim-mod-sync/scripts/play.sh" %command%
   ```

   路径要写绝对路径并加引号。之后从 Steam 启动游戏，每次都会自动先同步。

4. 验证：主菜单出现 `You are playing a modded version of Valheim`，`BepInEx/LogOutput.log` 里有各个 mod 的加载记录。

> 如果游戏装在别的 Steam 库，脚本会自动读 `libraryfolders.vdf`；仍找不到时可以手动指定：
> `VALHEIM_DIR="/path/to/Valheim" bash scripts/sync.sh`

## 首次设置 · Windows

1. 下载 `https://qinminbao.com/valheim/valheim-mod-sync.zip`（GitHub 能开也可以用仓库的 Code → Download ZIP），解压到固定位置，例如 `C:\valheim-mod-sync`。
2. 双击 `scripts\play.bat`。第一次会装 BepInEx 和全部 mod，然后启动游戏。
3. 想更自动（从 Steam 启动也会先同步）：Steam → 属性 → 启动选项，填：

   ```
   cmd /c ""C:\valheim-mod-sync\scripts\play.bat" %command%"
   ```

   注意首尾两层引号是必须的。

4. 如果之前用 r2modman 管过同一份游戏，**不要再用 r2modman 启动**，两套 BepInEx 会打架。

Windows 上不需要额外装 Git、Python 或 mod 管理器，PowerShell 系统自带。

## 日常：加 / 删 mod

在 Mac 上（仓库目录里）：

```bash
# 加：会自动下载校验、写入版本号和 SHA256
scripts/add-mod.sh ValheimModding Jotunn 2.30.2

# 删
scripts/add-mod.sh --remove Azumatt AzuAutoStore

# 发布到京东云（把清单和安装包同步上去，对方那边马上能拉到）
scripts/deploy-mirror.sh

# 留档
git add mods.json && git commit -m "add Jotunn 2.30.2" && git push
```

之后：

- 你这边启动游戏 → 自动装上；
- 她那边下次启动 → 自动装上。

两边都不需要手动下载。

## 同步规则

| 情况 | 行为 |
|---|---|
| 清单有、本机没有 | 下载安装 |
| 版本/哈希和清单不一致 | 重新下载替换 |
| 本机有、清单已删 | 移到 `BepInEx/plugins-disabled/`（不删除，随时能拿回来） |
| 下载失败 | 跳过该 mod 并报错；已装好的不受影响 |

- **哈希校验**：每个包都必须对上 `mods.json` 里的 SHA256，防止上游偷偷重新打包导致两边文件不同。
- **状态文件**：`BepInEx/plugins/.mod-sync-state.json`（Windows）/ `.mod-sync-state.tsv`（macOS），记录已装版本，不要手改。
- Windows 和 macOS 用的是同一批 Thunderstore 包（mod 本身是跨平台的托管 DLL），所以清单只需要一份。
- **安装包缓存**：`scripts/deploy-mirror.sh` 会把清单和所有 zip 发布到 `https://qinminbao.com/valheim/`，玩家端优先从这里下载；失败时自动退回 GitHub raw（清单）和 Thunderstore（安装包）。

## Mac 上要挑 mod

Mac 用 Metal 渲染，Windows 构建的资源包（新模型/贴图/怪物）容易变粉、变黑或隐形；纯逻辑类 mod 基本没问题。当前清单里都是逻辑/QoL 类。

加新的资源类 mod 时，先在 Mac 上单独试一次，坏了就 `--remove` 再推一次。

## 排错

- **Steam 点启动没反应**：启动选项路径写错（引号、空格、绝对路径）。
- **主菜单没有 modded version**：`bash scripts/sync.sh` 手动跑一次看报错；确认 `BepInEx/core/BepInEx.Preloader.dll` 存在。
- **进不去对方的房间 / 进去就掉线**：两边版本没对齐。看各自 `BepInEx/LogOutput.log` 里的 `Loading [名字 版本]` 行，逐条对比；让她重新双击 `play.bat`。
- **游戏更新后 mod 崩**：游戏补丁会打断 mod。两边先都更新游戏，再更新清单里的 mod 版本；实在崩可以 `git revert` 上一个 commit。
- **日志位置**：Mac `~/Library/Logs/IronGate/Valheim/Player.log`；Windows `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\Player.log`。

## 网络与镜像

默认从自己的服务器取：清单 `https://qinminbao.com/valheim/mods.json`，安装包 `https://qinminbao.com/valheim/packages/`。服务器连不上时脚本会自动退回 GitHub raw（清单）和 Thunderstore（安装包），哈希校验能保证退回来的文件和清单一致。

服务器上的内容要手动发布：改完清单跑一次 `scripts/deploy-mirror.sh`（默认 SSH 别名 `baosi-prod`）。

临时换地址可以在仓库根目录建 `mirror.txt`（已忽略，不需要提交），写一行清单地址；或直接设环境变量 `MANIFEST_URL` / `PACKAGE_BASE_URL`。

## 进阶：真正的"进服自动装"

如果想要"她加入服务器就自动下载 mod"，可以看专用服务器方案：

- [Valheim AutoModSync](https://www.nexusmods.com/valheim/mods/4006) — 服务端下发文件清单，客户端进服时自动下载并重启
- [ModGate](https://www.nexusmods.com/valheim/mods/4725) — 进服时列出一键下载

代价是需要有人一直开专用服务器，而且双方第一次仍要手动装这个同步 mod 本体。两个人玩的话，启动前同步一般更省事。
