#!/usr/bin/env python3
"""输出 TSV：namespace name version sha256（含 BepInEx 包），供部署脚本使用。"""

import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
pack = data["bepinex"]
print("\t".join([pack["namespace"], pack["name"], pack["version"], pack["sha256"]]))
for mod in data.get("mods", []):
    print("\t".join([mod["namespace"], mod["name"], mod["version"], mod["sha256"]]))
