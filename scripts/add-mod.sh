#!/usr/bin/env bash
# 往清单里加 / 删一个 mod，并写入正确的 SHA256。
#
# 用法:
#   scripts/add-mod.sh <namespace> <name> <version>
#   scripts/add-mod.sh --remove <namespace> <name>
#
# 例:
#   scripts/add-mod.sh ValheimModding Jotunn 2.30.2
#   scripts/add-mod.sh --remove Azumatt AzuAutoStore

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_DIR/mods.json"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

command -v curl    >/dev/null 2>&1 || die "找不到 curl"
command -v python3 >/dev/null 2>&1 || die "需要 python3"
[[ -f "$MANIFEST" ]] || die "找不到 $MANIFEST"

if [[ "${1:-}" == "--remove" ]]; then
  [[ $# -eq 3 ]] || die "用法：scripts/add-mod.sh --remove <namespace> <name>"
  python3 - "$MANIFEST" "$2" "$3" <<'PY'
import datetime, json, sys

path, ns, name = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path, encoding="utf-8"))
before = len(data.get("mods", []))
data["mods"] = [m for m in data.get("mods", [])
                if not (m["namespace"] == ns and m["name"] == name)]
if len(data["mods"]) == before:
    print(f"清单里没有 {ns}-{name}，未改动")
    sys.exit(0)
data["updatedAt"] = datetime.date.today().isoformat()
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"已从清单移除：{ns}-{name}")
PY
  exit 0
fi

[[ $# -eq 3 ]] || die "用法：scripts/add-mod.sh <namespace> <name> <version>"

ns="$1"
name="$2"
ver="$3"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://thunderstore.io/package/download/$ns/$name/$ver/"
printf '→ 下载 %s\n' "$ns-$name $ver"
curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$tmp/mod.zip" \
  || die "下载失败，检查命名空间/名字/版本号是否正确：$url"

sha="$(shasum -a 256 "$tmp/mod.zip" | awk '{print $1}')"

python3 - "$MANIFEST" "$ns" "$name" "$ver" "$sha" <<'PY'
import datetime, json, sys

path, ns, name, ver, sha = sys.argv[1:6]
data = json.load(open(path, encoding="utf-8"))
mods = data.setdefault("mods", [])

for m in mods:
    if m["namespace"] == ns and m["name"] == name:
        m["version"] = ver
        m["sha256"] = sha
        break
else:
    mods.append({"namespace": ns, "name": name, "version": ver, "sha256": sha})

data["updatedAt"] = datetime.date.today().isoformat()
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"已写入清单：{ns}-{name} {ver}")
PY

printf '\n下一步（在仓库目录执行）：\n'
printf '  git add mods.json && git commit -m "add %s %s" && git push\n' "$name" "$ver"
