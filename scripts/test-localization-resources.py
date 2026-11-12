#!/usr/bin/env python3
"""Offline regression checks for catalog validation and resource generation."""

import importlib.util
import json
from pathlib import Path
import plistlib
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock


RESOURCE_ROOT = Path(__file__).resolve().parents[1] / "Apps/Vyron/Resources"
SPEC = importlib.util.spec_from_file_location("vyron_resources", RESOURCE_ROOT / "generate_resources.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("The localization resource generator could not be loaded.")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def entry(english="A label", turkish="Bir etiket", ukrainian="Напис"):
    return {"localizations": {"en": unit(english), "tr": unit(turkish), "uk": unit(ukrainian)}}


def plural_entry():
    return {
        "localizations": {
            "en": {"variations": {"plural": {"one": unit("%d item"), "other": unit("%d items")}}},
            "tr": {"variations": {"plural": {"other": unit("%d öğe")}}},
            "uk": {"variations": {"plural": {
                "one": unit("%d елемент"),
                "few": unit("%d елементи"),
                "many": unit("%d елементів"),
                "other": unit("%d елемента"),
            }}},
        },
    }


class LocalizationResourceTests(unittest.TestCase):
    def test_missing_translation_is_rejected_in_every_supported_language(self):
        for language in ("en", "tr", "uk"):
            with self.subTest(language=language):
                catalog_entry = entry()
                del catalog_entry["localizations"][language]
                with self.assertRaisesRegex(SystemExit, f"Missing {language} translation"):
                    GENERATOR.localized_values({"example": catalog_entry})

    def test_untranslated_or_empty_values_are_rejected(self):
        for change in ({"state": "new"}, {"value": ""}):
            with self.subTest(change=change):
                catalog_entry = entry()
                catalog_entry["localizations"]["tr"]["stringUnit"].update(change)
                with self.assertRaisesRegex(SystemExit, "Untranslated tr value"):
                    GENERATOR.localized_values({"example": catalog_entry})

    def test_translation_cannot_change_a_parameter_type(self):
        catalog_entry = entry("%@ has %d items", "%@ için %d öğe", "%@ має %@ елементів")
        with self.assertRaisesRegex(SystemExit, "Mismatched uk format arguments"):
            GENERATOR.localized_values({"example": catalog_entry})

    def test_translation_can_reorder_parameters_by_position(self):
        catalog_entry = entry("%@ has %d items", "%2$d öğe: %1$@", "%2$d елементів: %1$@")
        values = GENERATOR.localized_values({"example": catalog_entry})
        self.assertEqual(set(values), {"en", "tr", "uk"})
        self.assertEqual(
            GENERATOR.format_signature(values["en"]["example"]),
            GENERATOR.format_signature(values["uk"]["example"]),
        )

    def test_escaped_percent_does_not_add_an_argument(self):
        self.assertEqual(GENERATOR.format_signature("Progress: %d%%"), {1: "d"})
        self.assertEqual(GENERATOR.format_signature("Literal %%d and %%@"), {})

    def test_ukrainian_requires_all_of_its_plural_categories(self):
        for category in ("one", "few", "many", "other"):
            with self.subTest(category=category):
                catalog_entry = plural_entry()
                del catalog_entry["localizations"]["uk"]["variations"]["plural"][category]
                with self.assertRaisesRegex(SystemExit, "Missing uk (plural forms|translation)"):
                    GENERATOR.localized_values({"example": catalog_entry})

    def test_each_plural_category_keeps_the_integer_count(self):
        catalog_entry = plural_entry()
        forms = catalog_entry["localizations"]["uk"]["variations"]["plural"]
        forms["few"] = unit("%@ елементи")
        with self.assertRaisesRegex(SystemExit, "Invalid uk plural form"):
            GENERATOR.localized_values({"example": catalog_entry})

    def test_plural_rules_produce_an_apple_stringsdict(self):
        catalog_entry = plural_entry()
        values = GENERATOR.localized_values({"example": catalog_entry})
        self.assertEqual(set(values), {"en", "tr", "uk"})
        for language, translation in catalog_entry["localizations"].items():
            with self.subTest(language=language):
                rule = GENERATOR.plural_dictionary(translation)
                self.assertEqual(rule["NSStringLocalizedFormatKey"], "%#@count@")
                self.assertEqual(rule["count"]["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType")
                self.assertEqual(rule["count"]["NSStringFormatValueTypeKey"], "d")
                expected_forms = translation["variations"]["plural"]
                actual_forms = set(rule["count"]) - {"NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"}
                self.assertEqual(actual_forms, set(expected_forms))
                for category, form in expected_forms.items():
                    self.assertEqual(rule["count"][category], form["stringUnit"]["value"])
                self.assertEqual(plistlib.loads(plistlib.dumps(rule)), rule)
        self.assertIsNone(GENERATOR.plural_dictionary(unit("An ordinary label")))

    def test_canonical_fallback_escaping_preserves_literal_backslashes(self):
        canonical = r'Path C:\new\value and literal \("text")'
        source = 'VyronResourceBundle.string("example", fallback: "normalized")'
        fixed = GENERATOR.escaped_fallbacks(source, {"example": canonical})
        fallback = json.loads(fixed.split("fallback: ", 1)[1][:-1])
        self.assertEqual(fallback, canonical)

    def test_literal_percent_is_escaped_only_in_the_swiftgen_input(self):
        literal = "Calculate 18% of 2450"
        swiftgen_inputs = []

        def capture_swiftgen(command, **_options):
            swiftgen_inputs.append(Path(command[-1]).read_text())
            return SimpleNamespace(returncode=0, stdout="// Generated fixture\n", stderr="")

        with tempfile.TemporaryDirectory(prefix="vyron-localization-test-") as temporary:
            fixture = Path(temporary)
            catalog = {"sourceLanguage": "en", "strings": {"appExample": entry(literal, literal, literal)}}
            (fixture / "Localizable.xcstrings").write_text(json.dumps(catalog))
            (fixture / "Symbols.json").write_text("{}")
            (fixture / "Strings.stencil").write_text((RESOURCE_ROOT / "Strings.stencil").read_text())
            with (
                mock.patch.object(GENERATOR, "ROOT", fixture),
                mock.patch.object(GENERATOR, "INFO_PLIST_KEYS", {}),
                mock.patch.object(GENERATOR, "color_outputs", return_value={}),
                mock.patch.object(GENERATOR.shutil, "which", return_value="/mocked/swiftgen"),
                mock.patch.object(GENERATOR.subprocess, "run", side_effect=capture_swiftgen),
            ):
                outputs = GENERATOR.outputs()
            self.assertEqual(len(swiftgen_inputs), 1)
            encoded = swiftgen_inputs[0].strip().split(" = ", 1)[1][:-1]
            self.assertEqual(json.loads(encoded), literal.replace("%", "%%"))
            for language in ("en", "tr", "uk"):
                runtime = outputs[fixture / f"{language}.lproj/Localizable.strings"]
                encoded = runtime.strip().split(" = ", 1)[1][:-1]
                self.assertEqual(json.loads(encoded), literal)

    def test_overlapping_namespaces_emit_each_key_only_in_its_most_specific_owner(self):
        inputs_by_namespace = {}

        def capture_swiftgen(command, **_options):
            source = Path(command[-1])
            inputs_by_namespace[source.parent.name] = {
                json.loads(line.split(" = ", 1)[0]) for line in source.read_text().splitlines()
            }
            return SimpleNamespace(returncode=0, stdout="// Generated fixture\n", stderr="")

        with tempfile.TemporaryDirectory(prefix="vyron-namespace-test-") as temporary:
            fixture = Path(temporary)
            catalog = {"sourceLanguage": "en", "strings": {
                "folderOpen": entry(),
                "folderAttachmentReady": entry(),
                "appExample": entry(),
                "modelDomainExample": entry(),
                "unprefixedExample": entry(),
            }}
            (fixture / "Localizable.xcstrings").write_text(json.dumps(catalog))
            (fixture / "Symbols.json").write_text("{}")
            (fixture / "Strings.stencil").write_text((RESOURCE_ROOT / "Strings.stencil").read_text())
            with (
                mock.patch.object(GENERATOR, "ROOT", fixture),
                mock.patch.object(GENERATOR, "SHARED_ROOT", fixture / "Shared"),
                mock.patch.object(GENERATOR, "INFO_PLIST_KEYS", {}),
                mock.patch.object(GENERATOR, "color_outputs", return_value={}),
                mock.patch.object(GENERATOR.shutil, "which", return_value="/mocked/swiftgen"),
                mock.patch.object(GENERATOR.subprocess, "run", side_effect=capture_swiftgen),
            ):
                outputs = GENERATOR.outputs()
            for language in ("en", "tr", "uk"):
                shared = fixture / f"Shared/Resources/{language}.lproj/Localizable.strings"
                self.assertIn('"modelDomainExample"', outputs[shared])
                self.assertNotIn('"appExample"', outputs[shared])
                self.assertNotIn('"modelDomainExample"', outputs[fixture / f"{language}.lproj/Localizable.strings"])

        self.assertEqual(inputs_by_namespace, {
            "VyronScheduledTaskText": {"unprefixedExample"},
            "VyronFolderText": {"folderOpen"},
            "VyronFolderAttachmentText": {"folderAttachmentReady"},
            "VyronAppText": {"appExample"},
            "VyronModelDomainText": {"modelDomainExample"},
        })

    def test_color_generation_requires_a_catalog(self):
        with tempfile.TemporaryDirectory(prefix="vyron-color-test-") as temporary:
            with mock.patch.object(GENERATOR, "ROOT", Path(temporary)):
                with self.assertRaisesRegex(SystemExit, "color catalog is missing"):
                    GENERATOR.color_outputs("/mocked/swiftgen")

    def test_color_generation_checks_exact_asset_membership_and_propagates_failure(self):
        with tempfile.TemporaryDirectory(prefix="vyron-color-test-") as temporary:
            root = Path(temporary)
            (root / "Theme.xcassets/EffortAccent.colorset").mkdir(parents=True)
            (root / "Theme.xcassets/EffortAccent.colorset/Contents.json").write_text(json.dumps({
                "colors": [{"idiom": "universal", "color": {
                    "color-space": "srgb", "components": {key: "1" for key in ("red", "green", "blue", "alpha")}
                }}]
            }))
            success = SimpleNamespace(returncode=0, stdout=(
                'enum VyronColors { static let effortAccent = '
                'VyronColorAssets.color(named: "EffortAccent") }\n'
            ), stderr="")
            with (
                mock.patch.object(GENERATOR, "ROOT", root),
                mock.patch.object(GENERATOR.subprocess, "run", return_value=success),
            ):
                output = GENERATOR.color_outputs("/mocked/swiftgen")
                self.assertEqual(output[root / "Generated/VyronColors.swift"], success.stdout)
                success.stdout = "// No assets found\n"
                with self.assertRaisesRegex(SystemExit, "do not match"):
                    GENERATOR.color_outputs("/mocked/swiftgen")
                success.returncode = 1
                success.stderr = "Color parser failed"
                with self.assertRaisesRegex(SystemExit, "Color parser failed"):
                    GENERATOR.color_outputs("/mocked/swiftgen")

    def test_color_catalog_rejects_unsupported_variants_and_invalid_components(self):
        with tempfile.TemporaryDirectory(prefix="vyron-color-test-") as temporary:
            catalog = Path(temporary) / "Theme.xcassets"
            color = catalog / "EffortAccent.colorset"
            color.mkdir(parents=True)
            valid = {"colors": [{"idiom": "universal", "color": {
                "color-space": "srgb", "components": {key: "1" for key in ("red", "green", "blue", "alpha")}
            }}]}
            for scenario in ("space", "appearance", "appearanceType", "idiom", "number", "boolean", "NaN", "-0.1", "1.1"):
                value = json.loads(json.dumps(valid))
                variant = value["colors"][0]
                if scenario == "space":
                    variant["color"]["color-space"] = "display-p3"
                elif scenario == "appearance":
                    variant["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
                elif scenario == "appearanceType":
                    variant["appearances"] = False
                elif scenario == "idiom":
                    variant["idiom"] = "iphone"
                elif scenario == "number":
                    variant["color"]["components"]["red"] = 1
                elif scenario == "boolean":
                    variant["color"]["components"]["red"] = True
                else:
                    variant["color"]["components"]["red"] = scenario
                (color / "Contents.json").write_text(json.dumps(value))
                with self.subTest(scenario=scenario), self.assertRaisesRegex(SystemExit, "Invalid color asset"):
                    GENERATOR.validate_color_catalog(catalog)


if __name__ == "__main__":
    unittest.main()
