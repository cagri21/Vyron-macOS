#!/usr/bin/env python3
"""Generate typed app strings, runtime localization, and SF Symbols from canonical inputs."""

import argparse
import json
import math
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
SHARED_ROOT = ROOT.parents[2] / "Packages/VyronLocalization"
LANGUAGES = ("en", "tr", "uk")
NAMESPACES = (
    ("VyronScheduledTaskText", ""),
    ("VyronPluginText", "plugins"),
    ("VyronSkillText", "skills"),
    ("VyronCompactionText", "compaction"),
    ("VyronConversationChangesText", "conversationChanges"),
    ("VyronWorkspaceText", "workspace"),
    ("VyronToolsText", "tools"),
    ("VyronBrowserText", "browser"),
    ("VyronChromeText", "chrome"),
    ("VyronHeaderText", "header"),
    ("VyronHandoffText", "handoff"),
    ("VyronNotificationText", "notification"),
    ("VyronBalanceText", "balance"),
    ("VyronBillingText", "billing"),
    ("VyronLocalAuthText", "localAuth"),
    ("VyronEstimatedBalanceText", "estimatedBalance"),
    ("VyronQueueText", "queue"),
    ("VyronQuestionText", "question"),
    ("VyronFolderText", "folder"),
    ("VyronFolderAttachmentText", "folderAttachment"),
    ("VyronProjectItemText", "projectItem"),
    ("VyronTrackingText", "tracking"),
    ("VyronModelRankingText", "modelRanking"),
    ("VyronSidebarText", "sidebar"),
    ("VyronVoiceText", "voice"),
    ("VyronScreenshotText", "screenshot"),
    ("VyronAutomationCenterText", "automationCenter"),
    ("VyronAppText", "app"),
    ("VyronLanguageText", "language"),
    ("VyronGeneralText", "general"),
    ("VyronStatusText", "status"),
    ("VyronControlText", "control"),
    ("VyronPrivacyText", "privacy"),
    ("VyronSettingsText", "settings"),
    ("VyronOfficeText", "office"),
)
SHARED_NAMESPACES = (
    ("VyronProjectApprovalText", "projectApproval"),
    ("VyronModelDomainText", "modelDomain"),
    ("VyronModelDataText", "modelData"),
)
INFO_PLIST_KEYS = {
    "NSMicrophoneUsageDescription": "privacyMicrophoneUsage",
    "NSSpeechRecognitionUsageDescription": "privacySpeechRecognitionUsage",
}


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def escaped_fallbacks(source, translations):
    # SwiftGen normalizes .strings escapes before rendering. Use canonical text
    # for Swift literals so literal backslashes cannot become interpolation.
    pattern = re.compile(
        r'(VyronResourceBundle\.(?:string|format)\(\s*)'
        r'("(?:[^"\\]|\\.)*")(\s*,\s*fallback:\s*)"(?:[^"\\]|\\.)*"'
    )

    def replace(match):
        value = quoted(translations[json.loads(match[2])])
        return match[1] + match[2] + match[3] + value

    return pattern.sub(replace, source)


def format_signature(value):
    """Compare argument positions and types, allowing translations to reorder them."""
    pattern = re.compile(r"%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?)(@|lld|ld|d|f|s|u)")
    arguments = {}
    cursor = 1
    for match in pattern.finditer(value.replace("%%", "")):
        position = int(match[1]) if match[1] else cursor
        arguments[position] = match[3]
        cursor += 1
    return arguments


def localized_values(strings):
    values = {language: {} for language in LANGUAGES}
    for name, entry in sorted(strings.items()):
        for language in LANGUAGES:
            try:
                translation = entry["localizations"][language]
                plural = translation.get("variations", {}).get("plural")
                unit = plural["other"]["stringUnit"] if plural else translation["stringUnit"]
                value = unit["value"]
            except KeyError as error:
                raise SystemExit(f"Missing {language} translation for {name}.") from error
            if unit.get("state") != "translated" or not value:
                raise SystemExit(f"Untranslated {language} value for {name}.")
            values[language][name] = value
            if plural:
                required = {
                    "en": {"one", "other"}, "tr": {"other"}, "uk": {"one", "few", "many", "other"}
                }[language]
                if not required.issubset(plural):
                    raise SystemExit(f"Missing {language} plural forms for {name}.")
                for form in plural.values():
                    form_unit = form["stringUnit"]
                    if form_unit.get("state") != "translated" or format_signature(form_unit["value"]) != {1: "d"}:
                        raise SystemExit(f"Invalid {language} plural form for {name}.")
        signature = format_signature(values["en"][name])
        if len(signature) > 4:
            raise SystemExit(f"Too many format arguments for {name}; compose a meaningful display value.")
        for language in LANGUAGES[1:]:
            if format_signature(values[language][name]) != signature:
                raise SystemExit(f"Mismatched {language} format arguments for {name}.")
    return values


def plural_dictionary(translation):
    plural = translation.get("variations", {}).get("plural")
    if not plural:
        return None
    return {
        "NSStringLocalizedFormatKey": "%#@count@",
        "count": {
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": "d",
            **{name: value["stringUnit"]["value"] for name, value in plural.items()},
        },
    }


def validate_color_catalog(catalog):
    names = set()
    for path in sorted(catalog.glob("*.colorset")):
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", path.stem) is None:
            raise SystemExit(f"Unsupported color asset name: {path.stem}")
        try:
            colors = json.loads((path / "Contents.json").read_text())["colors"]
            if not isinstance(colors, list) or len(colors) != 1 or colors[0]["idiom"] != "universal":
                raise ValueError("Use one universal color without appearance variants.")
            appearances = colors[0].get("appearances")
            if appearances is not None and (not isinstance(appearances, list) or appearances):
                raise ValueError("Appearance variants are not supported.")
            color = colors[0]["color"]
            if color["color-space"] != "srgb":
                raise ValueError("Only universal sRGB colors are supported.")
            components = [color["components"][key] for key in ("red", "green", "blue", "alpha")]
            if not all(isinstance(value, str) and value.strip() == value for value in components):
                raise ValueError("Color components must use canonical decimal strings.")
            values = [float(value) for value in components]
            if not all(math.isfinite(value) and 0 <= value <= 1 for value in values):
                raise ValueError("Color components must be finite values between zero and one.")
        except (OSError, KeyError, TypeError, IndexError, ValueError) as error:
            raise SystemExit(f"Invalid color asset {path.name}: {error}") from error
        names.add(path.stem)
    return names


def color_outputs(swiftgen):
    catalog = ROOT / "Theme.xcassets"
    if not catalog.is_dir():
        raise SystemExit("The canonical Theme.xcassets color catalog is missing.")
    names = validate_color_catalog(catalog)
    if not names:
        raise SystemExit("The canonical color catalog has no color assets.")
    result = subprocess.run(
        [swiftgen, "run", "xcassets", "--templatePath", str(ROOT / "Colors.stencil"), str(catalog)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr or result.stdout or "SwiftGen color generation failed.")
    emitted = set(re.findall(r'VyronColorAssets.color\(named: "([^"\n]+)"\)', result.stdout))
    if emitted != names:
        raise SystemExit("Generated color accessors do not match the canonical color catalog.")
    if len(result.stdout.splitlines()) > 400:
        raise SystemExit("Generated VyronColors exceeds 400 lines.")
    return {ROOT / "Generated/VyronColors.swift": result.stdout.rstrip("\n") + "\n"}


def outputs():
    catalog = json.loads((ROOT / "Localizable.xcstrings").read_text())
    strings = catalog["strings"]
    values = localized_values(strings)
    localized = {
        name: f"{quoted(name)} = {quoted(value if format_signature(value) else value.replace('%', '%%'))};"
        for name, value in values["en"].items()
    }
    swiftgen = shutil.which("swiftgen")
    if swiftgen is None:
        raise SystemExit("SwiftGen is required to generate or check typed localization resources.")
    generated = color_outputs(swiftgen)
    with tempfile.TemporaryDirectory(prefix="vyron-resources-") as temporary:
        all_namespaces = NAMESPACES + SHARED_NAMESPACES
        feature_prefixes = tuple(prefix for _, prefix in all_namespaces if prefix)
        for namespace, prefix in all_namespaces:
            shared = (namespace, prefix) in SHARED_NAMESPACES
            output_root = SHARED_ROOT if shared else ROOT
            directory = Path(temporary) / namespace
            directory.mkdir()
            entries = [
                value for name, value in localized.items()
                if prefix == max(
                    (candidate for candidate in feature_prefixes if name.startswith(candidate)),
                    key=len,
                    default="",
                )
            ]
            for index, offset in enumerate(range(0, len(entries), 35)):
                source = directory / "Localizable.strings"
                source.write_text("\n".join(entries[offset:offset + 35]) + "\n")
                template = directory / "Strings.stencil"
                content = (ROOT / "Strings.stencil").read_text()
                declaration = "enum VyronScheduledTaskText {"
                identifier = 'string.name|swiftIdentifier:"pretty"'
                if content.count(declaration) != 1 or identifier not in content:
                    raise SystemExit("The localization template no longer supports feature namespaces.")
                kind = "enum" if index == 0 else "extension"
                access = "package " if shared else ""
                content = content.replace(declaration, f"{access}{kind} {namespace} {{")
                if shared and index == 0:
                    content = content.replace("    static ", "    package static ")
                if prefix:
                    content = content.replace(identifier, f'string.name|replace:"{prefix}",""|swiftIdentifier:"pretty"')
                template.write_text(content)
                parameters = ["--param", "shared=true"] if shared else []
                result = subprocess.run(
                    [swiftgen, "run", "strings", "--templatePath", str(template), *parameters, str(source)],
                    capture_output=True, text=True,
                )
                if result.returncode:
                    raise SystemExit(result.stderr or result.stdout or "SwiftGen failed.")
                if len(result.stdout.splitlines()) > 400:
                    raise SystemExit(f"Generated {namespace} exceeds 400 lines; reduce the accessor chunk size.")
                suffix = "" if index == 0 else f"+{index + 1}"
                swift = escaped_fallbacks(result.stdout, values["en"])
                if shared:
                    swift = swift.replace("VyronResourceBundle.", "VyronSharedResources.current.")
                generated[output_root / f"Generated/{namespace}{suffix}.swift"] = swift.rstrip("\n") + "\n"
    symbols = json.loads((ROOT / "Symbols.json").read_text())
    symbol_lines = ["// Generated by Resources/generate_resources.py. Do not edit.", "", "enum VyronSymbols {"]
    symbol_lines.extend(f"    static let {name} = {quoted(value)}" for name, value in sorted(symbols.items()))
    symbol_lines.append("}")
    generated[ROOT / "Generated/VyronSymbols.swift"] = "\n".join(symbol_lines) + "\n"
    for language in LANGUAGES:
        generated[ROOT / f"{language}.lproj/InfoPlist.strings"] = "\n".join(
            f"{quoted(plist_key)} = {quoted(values[language][catalog_key])};"
            for plist_key, catalog_key in sorted(INFO_PLIST_KEYS.items())
        ) + "\n"
        shared_prefixes = tuple(prefix for _, prefix in SHARED_NAMESPACES)
        for shared, directory in ((False, ROOT), (True, SHARED_ROOT / "Resources")):
            owned = {
                name: value for name, value in values[language].items()
                if name.startswith(shared_prefixes) == shared
            }
            if shared and not owned:
                continue
            plurals = {
                name: rule for name in owned
                if (rule := plural_dictionary(strings[name]["localizations"][language])) is not None
            }
            localized_root = directory / f"{language}.lproj"
            generated[localized_root / "Localizable.strings"] = "\n".join(
                f"{quoted(name)} = {quoted(value)};" for name, value in owned.items() if name not in plurals
            ) + "\n"
            if plurals:
                generated[localized_root / "Localizable.stringsdict"] = plistlib.dumps(
                    plurals, sort_keys=True
                ).decode("utf-8")
    return generated


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    generated = outputs()
    owned = set((ROOT / "Generated").glob("Vyron*Text*.swift"))
    owned.update((SHARED_ROOT / "Generated").glob("Vyron*Text*.swift"))
    owned.update((ROOT / "Generated").glob("VyronColors*.swift"))
    for language in LANGUAGES:
        owned.update((ROOT / f"{language}.lproj").glob("Localizable.strings*"))
        owned.update((ROOT / f"{language}.lproj").glob("InfoPlist.strings"))
        owned.update((SHARED_ROOT / "Resources" / f"{language}.lproj").glob("Localizable.strings*"))
    unexpected = owned - set(generated)
    if unexpected:
        parser.exit(1, "Unexpected generated files: " + ", ".join(str(path) for path in sorted(unexpected)) + "\n")
    for path, content in generated.items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                stale.append(str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if stale:
        parser.exit(1, "Stale resources: " + ", ".join(stale) + "\n")
    print("Resource generation is current." if args.check else "Resources generated.")


if __name__ == "__main__":
    main()
