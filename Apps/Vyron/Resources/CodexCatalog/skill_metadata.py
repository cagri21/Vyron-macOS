"""Parse the small, inert metadata subset used by local SKILL.md documents."""

import json


def _quoted_end(value):
    quote = value[0]
    index = 1
    while index < len(value):
        if quote == '"' and value[index] == "\\":
            index += 2
            continue
        if value[index] == quote:
            if quote == "'" and index + 1 < len(value) and value[index + 1] == "'":
                index += 2
                continue
            return index
        index += 1
    return None


def _scalar(value):
    if value.startswith(('"', "'")):
        end = _quoted_end(value)
        if end is None or (value[end + 1:].strip() and not value[end + 1:].strip().startswith("#")):
            raise ValueError("Malformed skill metadata.")
        quoted = value[:end + 1]
        if quoted.startswith("'"):
            return quoted[1:-1].replace("''", "'")
        return json.loads(quoted.replace("\n", "\\n"))
    if value.startswith(("[", "{", "&", "*", "!")):
        raise ValueError("Unsupported skill metadata.")
    return value.split(" #", 1)[0]


def _body_description(lines):
    return next((line.strip() for line in lines
                 if line.strip() and not line.lstrip().startswith(("#", "```"))), "")


def parse_metadata(content, fallback_name):
    """Read name/description only; never evaluate YAML tags, aliases, or other values."""
    lines = content.replace("\r\n", "\n").lstrip("\ufeff").split("\n")
    name, description = fallback_name, ""
    body = lines
    if lines[0] == "---":
        end = next((index for index in range(1, len(lines)) if lines[index] in {"---", "..."}), None)
        if end is None:
            raise ValueError("The skill frontmatter is incomplete.")
        body = lines[end + 1:]
        index = 1
        while index < end:
            line = lines[index]
            index += 1
            if line.startswith((" ", "\t")) or ":" not in line:
                continue
            key, value = line.split(":", 1)
            if key not in {"name", "description"}:
                continue
            value = value.strip()
            if value in {">", ">-", ">+", "|", "|-", "|+"}:
                continuation = []
                while index < end and (lines[index].startswith(" ") or not lines[index]):
                    continuation.append(lines[index].strip())
                    index += 1
                parsed = (" " if value.startswith(">") else "\n").join(continuation)
            else:
                if value.startswith(('"', "'")):
                    while _quoted_end(value) is None and index < end:
                        if lines[index] and not lines[index].startswith(" "):
                            raise ValueError("Malformed quoted skill metadata.")
                        continuation = lines[index].strip()
                        value += " " + continuation if continuation else "\n"
                        index += 1
                else:
                    while index < end and lines[index].startswith(" "):
                        value += " " + lines[index].strip()
                        index += 1
                parsed = _scalar(value)
            if key == "name":
                name = parsed
            else:
                description = parsed
    name = name.strip()
    if not name or any(character in name for character in "\r\n\x00"):
        raise ValueError("The skill name is invalid.")
    return {
        "name": name[:160],
        "description": (description.strip() or _body_description(body))[:2_048],
    }
