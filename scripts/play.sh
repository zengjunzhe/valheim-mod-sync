#!/usr/bin/env bash
# macOS 启动器：先同步 mod，再用 BepInEx 启动 Valheim。
# Steam 启动项填：/bin/bash "/绝对路径/scripts/play.sh" %command%

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

bash "$SCRIPT_DIR/sync.sh" --quiet || echo "[mod-sync] 同步失败，按现有文件启动" >&2

V="$(resolve_valheim_dir)" || { echo "[mod-sync] 找不到 Valheim 目录，请设置 VALHEIM_DIR" >&2; exit 1; }

if [[ ! -f "$V/start_game_bepinex.sh" ]]; then
  echo "[mod-sync] 缺少 BepInEx 启动脚本，请先运行：bash \"$SCRIPT_DIR/sync.sh\"" >&2
  exit 1
fi

cd "$V"
exec /bin/bash "$V/start_game_bepinex.sh" "$@"
