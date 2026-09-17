-- ctl helpers, concatenated after ctl.luau (without `return ctl`).
local failed = 0

local function check(name, cond)
	if cond then
		print("ok - " .. name)
	else
		failed = failed + 1
		print("not ok - " .. name)
	end
end

local function join(list)
	return table.concat(list, " ")
end

check("json argv", join(ctl.jsonArgv({ "status" })) == "punktfunk-host ctl status --json")
check("watch argv", join(ctl.watchArgv()) == "punktfunk-host ctl watch --kinds pairing.*,stream.*,session.*,host.*")
check(
	"watch command quotes kinds",
	ctl.watchCommand() == "punktfunk-host ctl watch --kinds 'pairing.*,stream.*,session.*,host.*'"
)
check("watch needles", ctl.watchNeedles()[1] == "punktfunk-host" and ctl.watchNeedles()[2] == "watch")
check("list-monitors argv", join(ctl.listMonitorsArgv()) == "punktfunk-host list-monitors")
check("systemctl start", join(ctl.systemctlArgv("start")) == "systemctl --user start punktfunk-host.service")
check("xdg-open argv", ctl.xdgOpenArgv("https://example")[1] == "xdg-open")

local data, err = ctl.interpret({ data = { active_sessions = 1 } }, 0, "{}")
check("envelope data", data.active_sessions == 1 and err == nil)

local _, pinErr = ctl.interpret({ error = { code = 4, message = "pin mismatch" } }, 4, "")
check("envelope pin", ctl.isPinMismatch(pinErr) and pinErr.message == "pin mismatch")

local _, missing = ctl.interpret(nil, 127, "")
check("missing binary", missing.message == ctl.missingCtlMessage())

check("display path", ctl.displaySettingsPath("/home/lea/.config") == "/home/lea/.config/punktfunk/display-settings.json")
check("host env path", ctl.hostEnvPath("/home/lea/.config") == "/home/lea/.config/punktfunk/host.env")

check("env pin wins", ctl.captureModeFromConfig({ capture_monitor = nil }, "PUNKTFUNK_CAPTURE_MONITOR=DP-1\n") == "mirror")
check("settings mirror", ctl.captureModeFromConfig({ capture_monitor = "eDP-1" }, "") == "mirror")
check("default dedicated", ctl.captureModeFromConfig({}, "") == "dedicated")
check("null monitor dedicated", ctl.captureModeFromConfig({ capture_monitor = nil }, "") == "dedicated")

local stripped = ctl.stripCapturePin("FOO=1\nPUNKTFUNK_CAPTURE_MONITOR=DP-1\nBAR=2\n")
check("strip pin keeps others", stripped:find("FOO=1", 1, true) ~= nil and stripped:find("BAR=2", 1, true) ~= nil)
check("strip pin removes monitor", stripped:find("PUNKTFUNK_CAPTURE_MONITOR=", 1, true) == nil)

local applied = ctl.applyCaptureMonitor({ preset = "hotdesk", capture_monitor = "eDP-1" }, nil)
check("apply dedicated clears monitor", applied.capture_monitor == nil and applied.preset == "hotdesk")
local mirrored = ctl.applyCaptureMonitor({ preset = "hotdesk" }, "DP-3")
check("apply mirror sets connector", mirrored.capture_monitor == "DP-3")

local monitors = [[
Monitors:
  DP-1 1920x1080 [primary]
  HEADLESS-1 2560x1440 [punktfunk virtual display]
  HDMI-A-1 1280x720 [disabled]
]]
check("primary connector", ctl.primaryConnector(monitors) == "DP-1")

local sole = [[
Outputs
  eDP-1 2880x1800
]]
check("sole physical", ctl.primaryConnector(sole) == "eDP-1")

local none = [[
  HEADLESS-1 1920x1080 [punktfunk virtual display]
]]
check("virtual only rejected", ctl.primaryConnector(none) == nil)

check("console fallback", ctl.consoleUrlFromOutput("", 1) == "https://localhost:47992")
check("console minted", ctl.consoleUrlFromOutput("https://127.0.0.1:47992/login?t=abc\n", 0) == "https://127.0.0.1:47992/login?t=abc")
check("poll overview streaming", ctl.shouldPollStats(true, "overview", "streaming") == true)
check("no poll when closed", ctl.shouldPollStats(false, "overview", "streaming") == false)
check("no poll pair tab", ctl.shouldPollStats(true, "pair", "streaming") == false)
check("clear history on stop", ctl.eventClearsHistory("stream.stopped") == true)
check("host stopping", ctl.eventStopsHost("host.stopping") == true)
check("pairing completed refreshes clients", ctl.eventNeedsClients("pairing.completed") == true)

local decode = function(line)
	if line:find("resync", 1, true) then
		return { kind = "ctl.resync" }
	end
	return nil
end
local kind = ctl.eventKind('{"kind":"ctl.resync"}', decode)
check("event kind", kind == "ctl.resync")
check("empty line ignored", ctl.eventKind("", decode) == nil)

if failed > 0 then
	error(string.format("%d ctl checks failed", failed))
end
print("all ctl checks passed")
