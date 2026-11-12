"""Bounded, credential-free discovery of Claude, Codex, and shared skill files."""

import hashlib
import json
import os
from pathlib import Path
import stat

from security import CatalogError
from skill_metadata import parse_metadata


MAX_ENTRIES = 30_000
MAX_SKILLS = 1_000
MAX_DEPTH = 10
MAX_DOCUMENT_BYTES = 65_536
# Leave room below Vyron's 48,000-character tool-text limit for a valid JSON document.
MAX_RESULT_CHARACTERS = 40_000
SOURCES = {"all", "codex", "claude", "shared"}
SCOPES = {"all", "personal", "project", "plugin"}
EXCLUDED_DIRECTORIES = {"assets", "scripts", "references", "node_modules", "__pycache__"}


def _open_directory(path):
    """Open every ancestor from / without following symbolic links, including races."""
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise CatalogError("Skill roots must be absolute local directory paths.")
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in path.parts[1:]:
            following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = following
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _read_preview(root, relative):
    """Read only a fixed SKILL.md path, bounded even when it changes during reading."""
    if not relative.parts or relative.name != "SKILL.md" or relative.is_absolute() or ".." in relative.parts:
        raise CatalogError("Choose a skill ID returned by list_skills.")
    descriptors = []
    try:
        descriptor = _open_directory(root)
        descriptors.append(descriptor)
        for part in relative.parts[:-1]:
            descriptor = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            descriptors.append(descriptor)
        descriptor = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
        descriptors.append(descriptor)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise CatalogError("The skill is not a regular file.")
        content = bytearray()
        while len(content) <= MAX_DOCUMENT_BYTES:
            chunk = os.read(descriptor, min(16_384, MAX_DOCUMENT_BYTES + 1 - len(content)))
            if not chunk:
                break
            content.extend(chunk)
        truncated = len(content) > MAX_DOCUMENT_BYTES
        preview = bytes(content[:MAX_DOCUMENT_BYTES])
        # A byte limit may end inside one valid UTF-8 scalar; discard that suffix only.
        for suffix in range(4):
            try:
                decoded = (preview[:-suffix] if suffix else preview).decode("utf-8")
                return decoded, truncated
            except UnicodeError:
                if not truncated:
                    break
        raise CatalogError("The skill does not use supported UTF-8 text.")
    except OSError as error:
        raise CatalogError("The skill is missing, unreadable, or uses a symbolic link.") from error
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


class SkillsCatalog:
    def __init__(self, home_root, project_root=None):
        # Do not resolve(): root or ancestor symlinks must be rejected when opened.
        home = Path(os.path.abspath(os.path.expanduser(str(home_root))))
        self.roots = [
            (home / ".codex/skills", "codex", "personal"),
            (home / ".claude/skills", "claude", "personal"),
            (home / ".agents/skills", "shared", "personal"),
        ]
        if project_root is not None:
            project = Path(os.path.abspath(os.path.expanduser(str(project_root))))
            self.roots += [
                (project / ".codex/skills", "codex", "project"),
                (project / ".claude/skills", "claude", "project"),
                (project / ".agents/skills", "shared", "project"),
            ]
        self.roots += [
            (home / ".codex/plugins/cache", "codex", "plugin"),
            (home / ".claude/plugins/cache", "claude", "plugin"),
        ]

    def list_skills(self, query="", source="all", scope="all", offset=0, limit=25):
        if (not isinstance(query, str) or len(query) > 200
                or not isinstance(source, str) or source not in SOURCES
                or not isinstance(scope, str) or scope not in SCOPES
                or type(offset) is not int or offset < 0 or offset > 1_000_000
                or type(limit) is not int or not 1 <= limit <= 50):
            raise CatalogError("Choose supported source, scope, search, and pagination values.")
        inventory, state = self._inventory()
        needle = query.strip().casefold()
        entries = [item for item, _root, _relative in inventory
                   if (source == "all" or item["source"] == source)
                   and (scope == "all" or item["scope"] == scope)
                   and (not needle or needle in " ".join((item["name"], item["description"], item["path"])).casefold())]
        page = entries[offset:offset + limit]
        while True:
            result = {
                "skills": page, "total": len(entries),
                "next_offset": offset + len(page) if offset + len(page) < len(entries) else None,
                "scan_limited": state["limited"], "skipped_count": state["skipped"],
                "untrusted": True,
            }
            if len(json.dumps(result, ensure_ascii=False)) <= MAX_RESULT_CHARACTERS:
                return result
            if len(page) <= 1:
                raise CatalogError("The skill metadata exceeds the response limit.")
            page = page[:-1]

    def read_skill(self, skill_id):
        if not isinstance(skill_id, str) or len(skill_id) != 64:
            raise CatalogError("Choose a skill ID returned by list_skills.")
        inventory, _state = self._inventory()
        selected = next((entry for entry in inventory if entry[0]["id"] == skill_id), None)
        if selected is None:
            raise CatalogError("The skill is unavailable. Refresh list_skills and choose a current ID.")
        item, root, relative = selected
        content, truncated = _read_preview(root, relative)
        result = {**item, "content": content, "truncated": truncated, "untrusted": True,
                  "reference_only": True}
        if len(json.dumps(result, ensure_ascii=False)) <= MAX_RESULT_CHARACTERS:
            return result
        result["truncated"] = True
        # Escaped quotes, backslashes and control characters consume more serialized
        # characters than their source text. Fit the actual JSON text, not the raw body.
        lower, upper = 0, len(content)
        result["content"] = ""
        if len(json.dumps(result, ensure_ascii=False)) > MAX_RESULT_CHARACTERS:
            raise CatalogError("The skill metadata exceeds the response limit.")
        while lower < upper:
            middle = (lower + upper + 1) // 2
            result["content"] = content[:middle]
            if len(json.dumps(result, ensure_ascii=False)) <= MAX_RESULT_CHARACTERS:
                lower = middle
            else:
                upper = middle - 1
        result["content"] = content[:lower]
        return result

    def _inventory(self):
        inventory, visited = [], set()
        state = {"entries": 0, "skipped": 0, "limited": False, "exhausted": False}
        for root, source, scope in self.roots:
            if state["exhausted"]:
                break
            try:
                descriptor = _open_directory(root)
            except FileNotFoundError:
                continue
            except OSError:
                state["skipped"] += 1
                continue
            try:
                self._walk(descriptor, root, Path(), (source, scope), (inventory, visited, state))
            finally:
                os.close(descriptor)
        inventory.sort(key=lambda entry: (entry[0]["name"].casefold(), entry[0]["id"]))
        return inventory, state

    def _walk(self, descriptor, root, relative, labels, scan):
        inventory, visited, state = scan
        try:
            with os.scandir(descriptor) as iterator:
                for child in iterator:
                    if state["entries"] >= MAX_ENTRIES or len(inventory) >= MAX_SKILLS:
                        state["limited"] = True
                        state["exhausted"] = True
                        break
                    state["entries"] += 1
                    path = relative / child.name
                    try:
                        metadata = child.stat(follow_symlinks=False)
                        if stat.S_ISLNK(metadata.st_mode):
                            state["skipped"] += 1
                        elif stat.S_ISDIR(metadata.st_mode):
                            if child.name in EXCLUDED_DIRECTORIES or (child.name.startswith(".") and child.name != ".system"):
                                continue
                            if len(path.parts) >= MAX_DEPTH:
                                state["limited"] = True
                                continue
                            following = os.open(child.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                                dir_fd=descriptor)
                            try:
                                self._walk(following, root, path, labels, scan)
                            finally:
                                os.close(following)
                        elif child.name == "SKILL.md":
                            identity = str(root / path)
                            if identity in visited:
                                continue
                            visited.add(identity)
                            content, truncated = _read_preview(root, path)
                            details = parse_metadata(content, path.parent.name or root.name)
                            item = {**details, "id": hashlib.sha256(identity.encode("utf-8")).hexdigest(),
                                    "source": labels[0], "scope": labels[1], "path": identity,
                                    "truncated": truncated}
                            inventory.append((item, root, path))
                    except (OSError, CatalogError, ValueError):
                        state["skipped"] += 1
        except OSError:
            state["skipped"] += 1
