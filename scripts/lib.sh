#!/usr/bin/env bash
# 共用函数：解析 Valheim 安装目录（macOS）

resolve_valheim_dir() {
  if [[ -n "${VALHEIM_DIR:-}" ]]; then
    [[ -d "$VALHEIM_DIR" ]] || return 1
    printf '%s\n' "$VALHEIM_DIR"
    return 0
  fi

  local base="$HOME/Library/Application Support/Steam/steamapps/common/Valheim"
  if [[ -d "$base" ]]; then
    printf '%s\n' "$base"
    return 0
  fi

  # 第二个及以后的 Steam 库
  local vdf="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
  if [[ -f "$vdf" ]]; then
    local p
    while IFS= read -r p; do
      if [[ -d "$p/steamapps/common/Valheim" ]]; then
        printf '%s\n' "$p/steamapps/common/Valheim"
        return 0
      fi
    done < <(sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$vdf")
  fi

  return 1
}
