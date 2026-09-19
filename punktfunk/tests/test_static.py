import json
import pathlib
import shutil
import subprocess
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "punktfunk"
LUAU_FILES = {
    "widget.luau": ("update", "onClick", "onRightClick"),
    "panel.luau": ("onOpen", "onClose", "update", "tree"),
    "service.luau": ("onEnable", "update"),
    "shortcut.luau": ("onClick",),
    "model.luau": (),
    "ctl.luau": (),
}


class FixtureTests(unittest.TestCase):
    def test_plugin_toml_matches_catalog(self):
        plugin = tomllib.loads((PLUGIN / "plugin.toml").read_text())
        catalog = tomllib.loads((ROOT / "catalog.toml").read_text())
        self.assertEqual("luxus/punktfunk", plugin["id"])
        self.assertEqual(24, plugin["plugin_api"])
        self.assertEqual("luxus", plugin["author"])
        self.assertEqual("MIT OR Apache-2.0", plugin["license"])
        self.assertNotIn("min_noctalia", plugin)
        entry = catalog["plugin"][0]
        for key in ("id", "name", "version", "plugin_api", "author"):
            self.assertEqual(plugin[key], entry[key], key)
        self.assertEqual("0.2.0", plugin["version"])
        self.assertEqual("exclusive", plugin["panel"][0].get("keyboard_focus"))
        self.assertNotIn("Return", plugin["panel"][0].get("capture_keys", []))
        self.assertEqual("widget.luau", plugin["widget"][0]["entry"])
        self.assertEqual("panel.luau", plugin["panel"][0]["entry"])
        self.assertEqual("service.luau", plugin["service"][0]["entry"])
        self.assertEqual("shortcut.luau", plugin["shortcut"][0]["entry"])
        self.assertEqual("punktfunk-host", plugin["dependencies"][0])
        self.assertEqual("cast", plugin["icon"])
        self.assertTrue((PLUGIN / "punktfunk-logo.svg").is_file())
        self.assertTrue((PLUGIN / "assets" / "punktfunk-logo.svg").is_file())
        self.assertTrue((PLUGIN / "assets" / "punktfunk-mark.svg").is_file())
        logo = (PLUGIN / "assets" / "punktfunk-logo.svg").read_text()
        root_logo = (PLUGIN / "punktfunk-logo.svg").read_text()
        mark = (PLUGIN / "assets" / "punktfunk-mark.svg").read_text()
        self.assertEqual(logo, root_logo)
        self.assertIn("pf-wm", logo)
        self.assertIn("pf-back", logo)
        self.assertIn("pf-deep", logo)
        self.assertIn("viewBox=\"0 0 579 298\"", logo)
        self.assertNotIn("pf-wm", mark)
        self.assertIn("pf-back", mark)
        self.assertIn("pf-deep", mark)
        self.assertIn("viewBox=\"16 24 130 132\"", mark)
        assets_readme = (PLUGIN / "assets" / "README.md").read_text()
        self.assertIn("punktfunk-mark.svg", assets_readme)
        self.assertIn("lens", assets_readme.lower())
        self.assertIn("wordmark", assets_readme.lower())

    def test_translations_cover_plugin_settings(self):
        translations = json.loads((PLUGIN / "translations" / "en.json").read_text())
        plugin = tomllib.loads((PLUGIN / "plugin.toml").read_text())
        settings = translations["settings"]
        self.assertIn("show_label", settings)
        for block in plugin["setting"]:
            self.assertIn(block["key"], settings)
            self.assertEqual(f"settings.{block['key']}.label", block["label_key"])

    def test_readme_enable_path(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("luxus/punktfunk", readme)
        self.assertIn("noctalia msg plugins source add punktfunk git https://github.com/luxus/noctalia-punktfunk", readme)
        self.assertIn("noctalia msg plugins enable luxus/punktfunk", readme)
        self.assertIn("plugin_api", readme)
        self.assertIn("punktfunk-host ctl", readme)
        self.assertNotIn("QtQuick", readme)
        self.assertNotIn("omarchy-shell", readme)
        self.assertIn("standalone", readme.lower())
        self.assertIn("plugin_api` 24", readme)
        self.assertIn("noctalia.notify", readme)
        self.assertIn("punktfunk-logo.svg", readme)
        self.assertIn("punktfunk-mark.svg", readme)
        self.assertTrue((ROOT / "docs" / "parity.md").is_file())
        parity = (ROOT / "docs" / "parity.md").read_text()
        self.assertIn("noctalia.notify", parity)
        self.assertIn("ctl access", parity)
        self.assertIn("display release", parity)
        self.assertIn("punktfunk-logo.svg", parity)
        self.assertIn("PUNKTFUNK_10BIT", parity)
        self.assertIn("PUNKTFUNK_444", parity)
        self.assertIn("4:4:4 **allowed**", parity)
        self.assertIn("connected", parity.lower())
        self.assertIn("journalctl", parity)
        self.assertIn("ctl logs", parity)
        self.assertIn("title+body only", parity)
        self.assertIn("no actions", parity.lower())

    def test_luau_entrypoints_exist_and_are_not_qml(self):
        for name, functions in LUAU_FILES.items():
            text = (PLUGIN / name).read_text()
            self.assertTrue(text.startswith("--!nonstrict"), name)
            self.assertNotIn("QtQuick", text)
            self.assertNotIn("import Qt", text)
            self.assertNotIn("Quickshell", text)
            for function in functions:
                if function == "tree":
                    self.assertIn("function tree()", text, name)
                else:
                    self.assertIn("function %s(" % function, text, "%s %s" % (name, function))

    def test_ui_copy_is_english(self):
        panel = (PLUGIN / "panel.luau").read_text()
        model = (PLUGIN / "model.luau").read_text()
        widget = (PLUGIN / "widget.luau").read_text()
        translations = (PLUGIN / "translations" / "en.json").read_text()
        for name, text in (
            ("panel.luau", panel),
            ("model.luau", model),
            ("widget.luau", widget),
            ("en.json", translations),
        ):
            for needle in ("verbunden", "erlaubt", "trennen", "Erlaubt"):
                self.assertNotIn(needle, text, name)
            self.assertNotIn('return "ja"', text, name)
            self.assertNotIn('return "nein"', text, name)
        self.assertIn("HDR (connected)", model)
        self.assertIn("HDR allowed", panel)
        self.assertIn("Recording performance", panel)

    def test_bar_and_panel_use_punktfunk_logo(self):
        widget = (PLUGIN / "widget.luau").read_text()
        panel = (PLUGIN / "panel.luau").read_text()
        model = (PLUGIN / "model.luau").read_text()
        self.assertIn("punktfunk-mark.svg", widget)
        self.assertNotIn("punktfunk-logo.svg", widget)
        self.assertIn("ui.image", widget)
        self.assertIn("barWidget.render", widget)
        self.assertNotIn("barWidget.setImage", widget)
        self.assertIn("assets/punktfunk-logo.svg", panel)
        self.assertIn("ui.image", panel)
        self.assertIn("PANEL_LOGO_WIDTH", panel)
        self.assertNotIn("width = 28", panel)
        self.assertIn('MARK_PATH = "assets/punktfunk-mark.svg"', model)
        self.assertIn('LOGO_PATH = "assets/punktfunk-logo.svg"', model)
        self.assertIn("PANEL_LOGO_WIDTH = 140", model)
        self.assertNotIn("widgetChrome", widget)


    def test_luau_syntax_when_compiler_is_available(self):
        compiler = shutil.which("luau-compile")
        if compiler is None and pathlib.Path("/tmp/luau-bin/luau-compile").is_file():
            compiler = "/tmp/luau-bin/luau-compile"
        if not compiler:
            self.skipTest("luau-compile is not on PATH")
        for name in LUAU_FILES:
            result = subprocess.run(
                [compiler, "--binary", str(PLUGIN / name)],
                capture_output=True,
                timeout=15,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", "replace"))


if __name__ == "__main__":
    unittest.main()
