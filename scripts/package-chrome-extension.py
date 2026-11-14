#!/usr/bin/env python3
"""Create a local-test Chrome extension ZIP without uploading or installing it."""

import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "extensions" / "chrome"
RUNTIME_FILES = (
    "manifest.json", "worker.js", "session.js", "protocol.js", "dom.js",
    "popup.html", "popup.js", "popup.css",
    "icons/icon16.png", "icons/icon32.png", "icons/icon48.png", "icons/icon128.png",
)


def main():
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    if manifest.get("manifest_version") != 3:
        raise SystemExit("A Manifest V3 extension is required.")
    version = manifest.get("version", "")
    if not version or any(not part.isdigit() for part in version.split(".")):
        raise SystemExit("The extension version is invalid.")
    if set(manifest.get("permissions", [])) != {"activeTab", "scripting", "nativeMessaging"}:
        raise SystemExit("Review changed permissions before packaging.")
    if set(manifest.get("optional_permissions", [])) != {"tabGroups"}:
        raise SystemExit("Review changed optional permissions before packaging.")
    if any(manifest.get(key) for key in ("host_permissions", "optional_host_permissions", "externally_connectable")):
        raise SystemExit("Unexpected website or external connection access requires review.")
    sources = []
    for name in RUNTIME_FILES:
        path = SOURCE / name
        if not path.is_file() or path.is_symlink() or path.resolve().parent not in {SOURCE, SOURCE / "icons"}:
            raise SystemExit("Missing or unsafe extension file: " + name)
        sources.append((name, path.read_bytes()))
    directory = ROOT / ".build" / "chrome-testing"
    if directory.is_symlink() or (ROOT / ".build").is_symlink():
        raise SystemExit("The packaging output must not be a symbolic link.")
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ("vyron-chrome-" + version + ".zip")
    if target.is_symlink():
        raise SystemExit("The archive output must not be a symbolic link.")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sources:
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(target) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(RUNTIME_FILES):
            raise SystemExit("The extension archive could not be verified.")
    print(target)


if __name__ == "__main__":
    main()
