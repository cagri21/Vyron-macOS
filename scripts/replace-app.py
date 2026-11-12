#!/usr/bin/env python3
"""Build a fresh Vyron bundle, retire verified older copies, and replace the launch app."""

import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import uuid
from xml.parsers.expat import ExpatError


BUNDLE_ID = "ai.vyron.desktop"


def plain_ancestry(path: Path) -> bool:
    return path.is_absolute() and not any(item.is_symlink() for item in (path, *path.parents))


def is_vyron_app(path: Path) -> bool:
    """Inspect only app identity metadata; never follow a link to another location."""
    info = path / "Contents/Info.plist"
    executable = path / "Contents/MacOS/Vyron"
    if path.suffix.lower() != ".app" or not plain_ancestry(info) or not plain_ancestry(executable):
        return False
    if not path.is_dir() or not info.is_file() or not executable.is_file():
        return False
    try:
        with info.open("rb") as stream:
            metadata = plistlib.load(stream)
        return (
            isinstance(metadata, dict)
            and metadata.get("CFBundleIdentifier") == BUNDLE_ID
            and metadata.get("CFBundlePackageType") == "APPL"
            and metadata.get("CFBundleExecutable") == "Vyron"
        )
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError):
        return False


def previous_apps(project: Path, home: Path, applications: Path, staged_app: Path) -> list[Path]:
    candidates: set[Path] = set()
    build_root = project / ".build"
    stage_root = staged_app.parent
    if plain_ancestry(build_root) and build_root.is_dir():
        for directory, folders, _ in os.walk(build_root, followlinks=False):
            current = Path(directory)
            retained = []
            for name in folders:
                path = current / name
                if path == stage_root or path.is_symlink():
                    continue
                if path.suffix.lower() == ".app":
                    if is_vyron_app(path):
                        candidates.add(path)
                else:
                    retained.append(name)
            folders[:] = retained
    for directory in (home / "Desktop", home / "Applications", applications):
        if not plain_ancestry(directory) or not directory.is_dir():
            continue
        for path in directory.iterdir():
            if path != staged_app and not path.is_relative_to(stage_root) and is_vyron_app(path):
                candidates.add(path)
    return sorted(candidates, key=str)


def replace_apps(staged_app: Path, target: Path, old_apps: list[Path], trash: Path) -> None:
    if not is_vyron_app(staged_app):
        raise RuntimeError("The new Vyron app is not a valid app bundle. Older copies were preserved.")
    if staged_app == target or not plain_ancestry(target) or not plain_ancestry(trash):
        raise RuntimeError("App replacement paths must be separate local folders without symbolic links.")
    old_apps = list(dict.fromkeys(old_apps))
    if target.exists() and (target not in old_apps or not is_vyron_app(target)):
        raise RuntimeError(f"A different item already exists at {target}. It was preserved.")
    for app in old_apps:
        if not is_vyron_app(app) or staged_app.is_relative_to(app) or app.is_relative_to(trash):
            raise RuntimeError(f"An older app changed or has an unsafe location: {app}. No apps were moved.")
    trash.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    retired: list[tuple[Path, Path]] = []
    try:
        for app in old_apps:
            if not is_vyron_app(app):
                raise RuntimeError(f"An older app changed during replacement: {app}")
            destination = trash / f"{app.stem}-{uuid.uuid4().hex}.app"
            if destination.exists() or destination.is_symlink():
                raise RuntimeError(f"The Trash destination is occupied: {destination}")
            os.rename(app, destination)
            retired.append((app, destination))
        if target.exists() or target.is_symlink():
            raise RuntimeError(f"The installation path changed during replacement: {target}")
        os.rename(staged_app, target)
    except (OSError, RuntimeError) as error:
        rollback_errors = []
        for original, retired_app in reversed(retired):
            try:
                if original.exists() or original.is_symlink():
                    raise RuntimeError(f"The original path is occupied: {original}")
                os.rename(retired_app, original)
            except (OSError, RuntimeError) as rollback_error:
                rollback_errors.append(f"{retired_app}: {rollback_error}")
        if rollback_errors:
            raise RuntimeError(
                "App replacement failed. Some older copies remain recoverable in Trash: "
                + "; ".join(rollback_errors)
            ) from error
        raise RuntimeError(f"App replacement failed; older copies were restored: {error}") from error


def require_vyron_closed() -> None:
    result = subprocess.run(["/usr/bin/pgrep", "-x", "Vyron"], capture_output=True, text=True)
    if result.returncode == 0:
        raise RuntimeError("Quit Vyron first so any active task can finish or save, then run this shortcut again.")
    if result.returncode != 1:
        raise RuntimeError("Could not check whether Vyron is running. No app replacement was attempted.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="List verified older apps without changing them.")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    home = Path.home()
    build_root = project / ".build"
    target = build_root / "app/Vyron.app"
    if not plain_ancestry(build_root):
        raise RuntimeError("The build folder contains a symbolic link. No apps were changed.")
    if args.dry_run:
        placeholder = build_root / ".run-vyron-preview/Vyron.app"
        for app in previous_apps(project, home, Path("/Applications"), placeholder):
            print(app)
        return 0
    build_root.mkdir(exist_ok=True)
    lock_path = build_root / ".run-vyron.lock"
    if lock_path.is_symlink():
        raise RuntimeError("The app replacement lock contains a symbolic link.")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Another Run Vyron shortcut is already building or replacing the app.") from error
        require_vyron_closed()
        staging = Path(tempfile.mkdtemp(prefix=".run-vyron-", dir=build_root))
        staged_app = staging / "Vyron.app"
        print("Building the latest Vyron app…", flush=True)
        subprocess.run(
            ["/bin/zsh", str(project / "scripts/build-app.sh"), "debug", str(staged_app)],
            cwd=project, check=True,
        )
        require_vyron_closed()
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged_app)], check=True)
        older = previous_apps(project, home, Path("/Applications"), staged_app)
        print(f"Moving {len(older)} older Vyron app copies to Trash…", flush=True)
        replace_apps(staged_app, target, older, home / ".Trash")
        staging.rmdir()
        print(f"Installed the latest Vyron app: {target}", flush=True)
        try:
            subprocess.run(["/usr/bin/open", str(target)], check=True)
        except subprocess.CalledProcessError as error:
            raise RuntimeError(f"The latest Vyron app is installed, but macOS could not open it: {target}") from error
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Run Vyron failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
