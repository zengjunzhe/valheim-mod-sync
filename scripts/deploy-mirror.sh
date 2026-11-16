#!/usr/bin/env bash
# 把 mods.json、安装包和脚本包发布到京东云静态站。
#
# 用法:
#   scripts/deploy-mirror.sh [ssh别名]     # 默认 baosi-prod
#
# 环境变量:
#   REMOTE_DIR  远端目录（默认 /opt/base-stack/nginx/html/valheim）
#   BASE_URL    对外地址（默认 https://qinminbao.com/valheim）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:-baosi-prod}"
REMOTE_DIR="${REMOTE_DIR:-/opt/base-stack/nginx/html/valheim}"
BASE_URL="${BASE_URL:-https://qinminbao.com/valheim}"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "需要 python3"
command -v ssh     >/dev/null 2>&1 || die "需要 ssh"
command -v scp     >/dev/null 2>&1 || die "需要 scp"
command -v zip     >/dev/null 2>&1 || die "需要 zip"

python3 "$SCRIPT_DIR/validate.py" "$REPO_DIR/mods.json" || die "清单校验失败，未发布"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ 目标：$HOST:$REMOTE_DIR"

ssh "$HOST" "mkdir -p '$REMOTE_DIR/packages'"

# ---------- 1. mods.json ----------
scp -q "$REPO_DIR/mods.json" "$HOST:$REMOTE_DIR/mods.json.tmp"
ssh "$HOST" "mv '$REMOTE_DIR/mods.json.tmp' '$REMOTE_DIR/mods.json'"
echo "✓ mods.json"

# ---------- 2. 安装包（服务器直接从 Thunderstore 拉，校验 SHA256） ----------
{
  cat <<'HEAD'
set -eu
cd "$REMOTE_DIR/packages"
while IFS=$'\t' read -r ns name ver sha; do
  [ -n "$ns" ] || continue
  f="$ns-$name-$ver.zip"
  if [ -f "$f" ] && echo "$sha  $f" | sha256sum -c - >/dev/null 2>&1; then
    echo "= $f"
    continue
  fi
  curl -fsSL --retry 3 --connect-timeout 15 \
    "https://thunderstore.io/package/download/$ns/$name/$ver/" -o "$f.tmp"
  echo "$sha  $f.tmp" | sha256sum -c - >/dev/null
  mv "$f.tmp" "$f"
  echo "+ $f"
done <<'PKGS'
HEAD
  python3 "$SCRIPT_DIR/print_packages.py" "$REPO_DIR/mods.json"
  echo "PKGS"
} | ssh "$HOST" "REMOTE_DIR='$REMOTE_DIR' bash -s"

# ---------- 3. 脚本包（没网/没有 Git 的机器可以直接下载） ----------
(
  cd "$REPO_DIR"
  zip -qr "$TMP/valheim-mod-sync.zip" . \
    -x ".git/*" -x "mirror.txt" -x ".DS_Store" -x "*/.DS_Store"
)
scp -q "$TMP/valheim-mod-sync.zip" "$HOST:$REMOTE_DIR/valheim-mod-sync.zip.tmp"
ssh "$HOST" "mv '$REMOTE_DIR/valheim-mod-sync.zip.tmp' '$REMOTE_DIR/valheim-mod-sync.zip'"
echo "✓ valheim-mod-sync.zip"

# ---------- 4. 线上验证 ----------
echo "→ 验证："
for path in "mods.json" "valheim-mod-sync.zip" "packages/denikson-BepInExPack_Valheim-5.4.2360.zip"; do
  code="$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 20 -r 0-0 "$BASE_URL/$path")"
  printf '  %-60s HTTP %s\n' "$path" "$code"
  [[ "$code" == "206" || "$code" == "200" ]] || die "验证失败：$BASE_URL/$path"
done

echo "完成。玩家端可直接用："
echo "  清单 $BASE_URL/mods.json"
echo "  安装包 $BASE_URL/packages/"
