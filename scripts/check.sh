#!/usr/bin/env bash
# 检查 mod 是否真的被 BepInEx 加载成功（macOS）
#
# 用法: bash scripts/check.sh
# 环境变量: VALHEIM_DIR / LOG_FILE / MANIFEST_FILE

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [[ -n "${VALHEIM_DIR:-}" ]]; then
  V="$VALHEIM_DIR"
else
  V="$(resolve_valheim_dir)" || { echo "✗ 找不到 Valheim 目录，设置 VALHEIM_DIR 后重试"; exit 2; }
fi

LOG="${LOG_FILE:-$V/BepInEx/LogOutput.log}"
MANIFEST="${MANIFEST_FILE:-$REPO_DIR/mods.json}"

echo "游戏目录：$V"

if [[ ! -f "$V/BepInEx/core/BepInEx.Preloader.dll" ]]; then
  echo "✗ BepInEx 没装好（缺 BepInEx/core/BepInEx.Preloader.dll），先跑 scripts/sync.sh"
  exit 2
fi

if [[ ! -f "$LOG" ]]; then
  echo "✗ 还没有 BepInEx/LogOutput.log"
  echo "  说明装好之后还没通过 play.sh 启动过，或者 Steam 启动项没生效。"
  echo "  从 Steam 启动游戏、进到主菜单，然后再跑一次本脚本。"
  exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "需要 python3"; exit 2; }

python3 - "$MANIFEST" "$LOG" <<'PY'
import json
import re
import sys

manifest_path, log_path = sys.argv[1], sys.argv[2]

data = json.load(open(manifest_path, encoding="utf-8"))
expected = []
for mod in data.get("mods", []):
    # 依赖库通常没有 BepInPlugin，不会出现在 Loading 行里
    is_lib = mod["name"].lower() in {"yamldotnet"}
    expected.append((f"{mod['namespace']}-{mod['name']}", mod["name"], mod["version"], is_lib))

log = open(log_path, encoding="utf-8", errors="replace").read()
loaded = {}
for m in re.finditer(r"Loading \[(.+?)\]\s*$", log, re.M):
    entry = m.group(1).strip()
    parts = entry.rsplit(" ", 1)
    if len(parts) != 2:
        continue
    name, version = parts
    loaded[re.sub(r"[^a-z0-9]", "", name.lower())] = (name, version)

def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())

ok = 0
bad = 0
print()
print(f"{'包':52} {'期望':16} 结果")
print("-" * 96)
for pkg_id, name, version, is_lib in expected:
    key = norm(name)
    if key not in loaded:
        if is_lib:
            print(f"{pkg_id:52} {version:16} = 依赖库（不单独加载）")
        else:
            print(f"{pkg_id:52} {version:16} ✗ 未加载")
            bad += 1
        continue
    loaded_name, loaded_version = loaded[key]
    if loaded_version == version:
        print(f"{pkg_id:52} {version:16} ✓ 已加载")
        ok += 1
    else:
        print(f"{pkg_id:52} {version:16} ✗ 版本不一致（日志是 {loaded_version}）")
        bad += 1

expected_keys = {norm(name) for _, name, _, _ in expected}
extra = [v[0] for k, v in loaded.items() if k not in expected_keys]

print()
print(f"通过 {ok} 个，问题 {bad} 个")
if extra:
    print("清单外但已加载：" + "、".join(extra))
if bad:
    print("→ 先重跑 scripts/sync.sh；仍不一致就把上面这张表和 BepInEx/LogOutput.log 发给对方。")
    sys.exit(1)
print("→ 全部匹配。游戏里也应该能看到 mod 效果（手柄 mod 按 F8）。")
PY
