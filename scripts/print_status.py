#!/usr/bin/env python3
"""生成 SYNC-STATUS.md：让 AI / 玩家比对「期望装成什么样」。"""

import datetime
import hashlib
import json
import sys

path = sys.argv[1]
raw = open(path, "rb").read()
data = json.loads(raw)

lines = [
    "# Sync Status",
    "",
    f"- 生成时间：{datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
    f"- 清单地址：https://qinminbao.com/valheim/mods.json",
    f"- 清单 SHA256：{hashlib.sha256(raw).hexdigest()}",
    "",
    "## BepInEx",
    "",
    f"- {data['bepinex']['namespace']}-{data['bepinex']['name']} {data['bepinex']['version']}",
    "",
    "## Mods",
    "",
    "| 包 | 版本 |",
    "| --- | --- |",
]

for mod in data.get("mods", []):
    lines.append(f"| {mod['namespace']}-{mod['name']} | {mod['version']} |")

lines += [
    "",
    "本文件由 `scripts/deploy-mirror.sh` 自动生成，请勿手工编辑。",
    "比对方法：看本机 `BepInEx/LogOutput.log` 里每一条 `Loading [名字 版本]`。",
]

print("\n".join(lines))
