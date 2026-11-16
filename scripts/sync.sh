#!/usr/bin/env bash
# Valheim mod 同步脚本（macOS）
#
# 用法:
#   bash scripts/sync.sh            # 拉取清单并同步
#   bash scripts/sync.sh --quiet    # 静默模式（play.sh 使用）
#
# 环境变量:
#   VALHEIM_DIR    手动指定游戏目录（包含 valheim.app 的那一层）
#   MANIFEST_FILE  使用本地清单文件（离线 / 测试）
#   MANIFEST_URL   覆盖远程清单地址

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/zengjunzhe/valheim-mod-sync/main/mods.json}"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

say() { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "需要 python3：运行 xcode-select --install 安装命令行工具后再试。"
command -v curl    >/dev/null 2>&1 || die "找不到 curl。"
command -v unzip   >/dev/null 2>&1 || die "找不到 unzip。"

V="$(resolve_valheim_dir)" || die "找不到 Valheim 目录。请设置 VALHEIM_DIR 指向包含 valheim.app 的文件夹。"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- 1. 取清单 ----------
if [[ -n "${MANIFEST_FILE:-}" ]]; then
  cp "$MANIFEST_FILE" "$TMP/mods.json"
  say "清单：本地文件 $MANIFEST_FILE"
else
  curl -fsSL --retry 2 --connect-timeout 10 -H 'Cache-Control: no-cache' \
    "$MANIFEST_URL?ts=$(date +%s)" -o "$TMP/mods.json" \
    || die "拉取清单失败：$MANIFEST_URL"
  say "清单：$MANIFEST_URL"
fi

# 转成 TSV：kind  ns  name  version  sha256
python3 - "$TMP/mods.json" > "$TMP/plan.tsv" <<'PY'
import json, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
b = data["bepinex"]
print("\t".join(["bepinex", b["namespace"], b["name"], b["version"], b["sha256"]]))
for m in data.get("mods", []):
    print("\t".join(["mod", m["namespace"], m["name"], m["version"], m["sha256"]]))
PY

download_verify() {
  local url="$1" sha="$2" out="$3"
  curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$out" || return 1
  local got
  got="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [[ "$got" != "$sha" ]]; then
    warn "哈希不匹配（上游可能重新打包了）：$url"
    return 1
  fi
  return 0
}

# unzip 对 Windows 路径分隔符只给警告并返回 1，这种情况仍然解压成功
extract_zip() {
  local zip="$1" dest="$2" rc=0
  unzip -q "$zip" -d "$dest" || rc=$?
  [[ "$rc" -le 1 ]]
}

# 有些包把文件放在 plugins/ 子目录里，这里把它提上来
flatten_mod_dir() {
  local dir="$1"
  if [[ -d "$dir/plugins" ]]; then
    (cd "$dir/plugins" && tar cf - .) | (cd "$dir" && tar xf -)
    rm -rf "$dir/plugins"
  fi
  if [[ -d "$dir/config" ]]; then
    mkdir -p "$V/BepInEx/config"
    (cd "$dir/config" && tar cf - .) | (cd "$V/BepInEx/config" && tar xf -)
    rm -rf "$dir/config"
  fi
}

# ---------- 2. 准备目录与状态 ----------
PLUGINS="$V/BepInEx/plugins"
STATE="$PLUGINS/.mod-sync-state.tsv"
mkdir -p "$PLUGINS"
touch "$STATE"
: > "$TMP/newstate"

installed=0
skipped=0
removed=0
failed=0
pack_ready=0

# ---------- 3. 逐个处理 ----------
while IFS=$'\t' read -r kind ns name ver sha; do
  id="$ns-$name"

  if [[ "$kind" == "bepinex" ]]; then
    marker="$V/BepInEx/.mod-sync-bepinex"
    if [[ -f "$marker" ]] \
      && [[ "$(cat "$marker")" == "$id $ver $sha" ]] \
      && [[ -f "$V/BepInEx/core/BepInEx.Preloader.dll" ]]; then
      say "= BepInEx $ver"
      pack_ready=1
      continue
    fi

    say "→ BepInEx $ver"
    if ! download_verify "https://thunderstore.io/package/download/$ns/$name/$ver/" "$sha" "$TMP/bepinex.zip"; then
      die "BepInEx 下载失败，已中止（游戏目录未改动）"
    fi
    rm -rf "$TMP/bepinex"
    mkdir -p "$TMP/bepinex"
    extract_zip "$TMP/bepinex.zip" "$TMP/bepinex" || die "BepInEx 包解压失败"

    # 包里可能有 README 等散文件，真正的根目录是含有 start_game_bepinex.sh 的那层
    src="$(find "$TMP/bepinex" -name start_game_bepinex.sh -print -quit 2>/dev/null || true)"
    if [[ -n "$src" ]]; then
      src="$(dirname "$src")"
    else
      src="$TMP/bepinex"
    fi

    (cd "$src" && tar cf - .) | (cd "$V" && tar xf -)
    chmod +x "$V/start_game_bepinex.sh" 2>/dev/null || true
    mkdir -p "$V/BepInEx"
    printf '%s %s %s\n' "$id" "$ver" "$sha" > "$marker"
    pack_ready=1
    continue
  fi

  dir="$PLUGINS/$id"
  current="$(awk -F'\t' -v id="$id" -v v="$ver" -v s="$sha" \
    '$1==id && $2==v && $3==s { print "ok"; exit }' "$STATE")"

  if [[ "$current" == "ok" && -d "$dir" ]]; then
    printf '%s\t%s\t%s\n' "$id" "$ver" "$sha" >> "$TMP/newstate"
    skipped=$((skipped + 1))
    continue
  fi

  say "→ $id $ver"
  if ! download_verify "https://thunderstore.io/package/download/$ns/$name/$ver/" "$sha" "$TMP/$id.zip"; then
    warn "跳过 $id（下载或校验失败）"
    failed=$((failed + 1))
    # 保留原有状态，避免下次误判成“从未装过”
    awk -F'\t' -v id="$id" '$1==id' "$STATE" >> "$TMP/newstate"
    continue
  fi

  rm -rf "$dir"
  mkdir -p "$dir"
  if ! extract_zip "$TMP/$id.zip" "$dir"; then
    warn "解压失败：$id"
    failed=$((failed + 1))
    awk -F'\t' -v id="$id" '$1==id' "$STATE" >> "$TMP/newstate"
    continue
  fi
  flatten_mod_dir "$dir"
  installed=$((installed + 1))
  printf '%s\t%s\t%s\n' "$id" "$ver" "$sha" >> "$TMP/newstate"
done < "$TMP/plan.tsv"

# ---------- 4. 停用清单里已不存在的 mod ----------
while IFS=$'\t' read -r id ver sha; do
  [[ -n "$id" ]] || continue
  if grep -q "^$id"$'\t' "$TMP/newstate"; then
    continue
  fi
  if [[ -d "$PLUGINS/$id" ]]; then
    mkdir -p "$V/BepInEx/plugins-disabled"
    dest="$V/BepInEx/plugins-disabled/$id-$(date +%Y%m%d-%H%M%S)"
    mv "$PLUGINS/$id" "$dest"
    say "− 停用 $id（移到 plugins-disabled）"
    removed=$((removed + 1))
  fi
done < "$STATE"

mv "$TMP/newstate" "$STATE"

# ---------- 5. 结果 ----------
summary="完成：安装/更新 $installed 个，已是最新 $skipped 个，停用 $removed 个"
if [[ "$failed" -gt 0 ]]; then
  summary="$summary，失败 $failed 个"
fi
say "$summary"

if [[ "$pack_ready" -eq 0 ]]; then
  warn "BepInEx 未就绪，游戏可能无法加载 mod"
fi

if [[ "$QUIET" -eq 0 ]]; then
  say ""
  say "Mac 启动方式（Steam → 右键 Valheim → 属性 → 启动选项）："
  say "  /bin/bash \"$SCRIPT_DIR/play.sh\" %command%"
fi

exit 0
