import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "punktfunk"


class HostBoundaryTests(unittest.TestCase):
    def test_service_is_the_only_spawn_site(self):
        service = (PLUGIN / "service.luau").read_text()
        panel = (PLUGIN / "panel.luau").read_text()
        widget = (PLUGIN / "widget.luau").read_text()
        self.assertIn('runAsync(ctl.jsonArgv', service)
        self.assertIn("punktfunk-host", service)
        self.assertIn("ctl watch", service)
        self.assertIn("runStream", service)
        self.assertIn("processMatches", service)
        self.assertIn("watchNeedles", service)
        self.assertIn("--kinds '", (PLUGIN / "ctl.luau").read_text())
        self.assertNotIn("noctalia.runAsync", panel)
        self.assertNotIn("noctalia.runStream", panel)
        self.assertNotIn("noctalia.runAsync", widget)
        self.assertIn('noctalia.state.set("request"', panel)
        self.assertIn('noctalia.state.set("request"', widget)

    def test_argv_form_not_shell_interpolation(self):
        service = (PLUGIN / "service.luau").read_text()
        ctl = (PLUGIN / "ctl.luau").read_text()
        self.assertIn('local argv = { ctl.hostBin(), "ctl" }', ctl)
        self.assertIn('table.insert(argv, "--json")', ctl)
        self.assertIn("plugin_api 24", service)
        self.assertNotIn("curl ", service)
        self.assertNotIn("wget ", service)

    def test_no_operator_token_and_no_https_client(self):
        for name in ("service.luau", "panel.luau", "widget.luau", "ctl.luau"):
            text = (PLUGIN / name).read_text()
            self.assertNotIn("Authorization", text)
            self.assertNotIn("Bearer", text)
            self.assertNotIn("noctalia.http", text)
            self.assertNotIn("allow_insecure_tls", text)
        ctl = (PLUGIN / "ctl.luau").read_text()
        self.assertIn("never https", ctl.lower())
        self.assertIn("https://localhost:47992", ctl)
        service = (PLUGIN / "service.luau").read_text()
        self.assertNotIn("noctalia.http(", service)

    def test_core_surface_is_wired(self):
        service = (PLUGIN / "service.luau").read_text()
        panel = (PLUGIN / "panel.luau").read_text()
        model = (PLUGIN / "model.luau").read_text()
        for token in (
            '"status"',
            '"pending"',
            '"pair"',
            '"approve"',
            '"deny"',
            '"unpair"',
            '"stop-session"',
            '"end-game"',
            '"display"',
            '"stats"',
            "capture-mode",
        ):
            self.assertIn(token, service)
        for tab in ("overview", "pair", "devices", "display", "stats"):
            self.assertIn(tab, model)
        self.assertIn("Accept", panel)
        self.assertIn("Reject", panel)
        self.assertIn("Unpair", panel)
        self.assertIn("Dedicated", panel)
        self.assertIn("This screen", panel)
        self.assertIn("Stop the session", model)
        self.assertIn("function tree()", panel)
        self.assertNotIn('error("Punktfunk', panel)

    def test_display_mode_does_not_call_omarchy_helper(self):
        for name in ("service.luau", "panel.luau", "ctl.luau"):
            text = (PLUGIN / name).read_text()
            self.assertNotIn('punktfunk-omarchy"', text)
            self.assertNotIn("punktfunk-omarchy mode", text)
        ctl = (PLUGIN / "ctl.luau").read_text()
        self.assertIn("display-settings.json", ctl)
        self.assertIn("list-monitors", ctl)


if __name__ == "__main__":
    unittest.main()
