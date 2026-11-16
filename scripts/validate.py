#!/usr/bin/env python3
"""校验 mods.json 的结构。用法：python3 scripts/validate.py [mods.json]"""

import json
import re
import sys

SHA_RE = re.compile(r"^[0-9a-f]{64}$")


def fail(msg: str) -> None:
    print(f"✗ {msg}")
    sys.exit(1)


def check_pkg(pkg: dict, where: str) -> str:
    for key in ("namespace", "name", "version", "sha256"):
        if not isinstance(pkg.get(key), str) or not pkg[key].strip():
            fail(f"{where}: 缺少或为空的字段 {key}")
    pkg_id = f"{pkg['namespace']}-{pkg['name']}"
    if "-" in pkg["namespace"]:
        fail(f"{where}: namespace 不应包含连字符：{pkg['namespace']}")
    if not SHA_RE.match(pkg["sha256"]):
        fail(f"{where}: sha256 不是 64 位小写十六进制：{pkg_id}")
    return pkg_id


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else "mods.json"
    try:
        data = json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        fail(f"找不到 {path}")
    except json.JSONDecodeError as exc:
        fail(f"{path} 不是合法 JSON：{exc}")

    if data.get("schemaVersion") != 1:
        fail("schemaVersion 必须是 1")

    bepinex = data.get("bepinex")
    if not isinstance(bepinex, dict):
        fail("缺少 bepinex 段")
    check_pkg(bepinex, "bepinex")

    mods = data.get("mods")
    if not isinstance(mods, list) or not mods:
        fail("mods 必须是非空数组")

    seen: set[str] = set()
    for i, mod in enumerate(mods):
        mod_id = check_pkg(mod, f"mods[{i}]")
        if mod_id in seen:
            fail(f"重复的 mod：{mod_id}")
        seen.add(mod_id)

    print(f"✓ {path}: {len(mods)} 个 mod + BepInEx {bepinex['version']}")


if __name__ == "__main__":
    main()
