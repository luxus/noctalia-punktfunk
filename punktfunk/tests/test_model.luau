-- Model state machine, concatenated after model.luau (without `return model`)
-- so `model` is in scope. nixpkgs/official luau has no Noctalia require().
local failed = 0

local function check(name, cond)
	if cond then
		print("ok - " .. name)
	else
		failed = failed + 1
		print("not ok - " .. name)
	end
end

local function deepK(rows)
	local out = {}
	for i, row in ipairs(rows) do
		out[i] = row.k .. "=" .. row.v
	end
	return table.concat(out, "|")
end

check("mbps 300000", model.mbps(300000) == "300.0")
check("mbps 0", model.mbps(0) == "0.0")
check("mbps nil", model.mbps(nil) == "0.0")

check("dur 15 us", model.dur(15) == "15 µs")
check("dur 2321 ms", model.dur(2321) == "2.3 ms")
check("dur 1000", model.dur(1000) == "1.0 ms")

check("tail short", model.tail("abc") == "abc")
check("tail long", model.tail("0123456789abcdef") == "…6789abcdef")
check("tail empty", model.tail("") == "—")

local a = model.heroPhrase(0)
local b = model.heroPhrase(#model.ACTIVE_PHRASES)
check("hero wrap", a == b and #a > 0)
check("hero negative", model.heroPhrase(-1) == model.ACTIVE_PHRASES[#model.ACTIVE_PHRASES])

check("hero streaming client", model.heroTitle("streaming", "iPad") == "iPad")
check("hero idle keeps brand", model.heroTitle("idle", "iPad") == "Punktfunk")
check("hero stopped", model.heroTitle("stopped") == "Punktfunk")

check("hero meta streaming", model.heroMeta("streaming", "Pushing pixels") == "Pushing pixels")
check("hero meta idle", model.heroMeta("idle") == "Ready to stream")
check("hero meta stopped", model.heroMeta("stopped") == "Host is stopped")

check("capture dedicated", model.captureModeStatus("dedicated\n") == "dedicated")
check("capture mirror", model.captureModeStatus(" mirror ") == "mirror")
check("capture connector rejected", model.captureModeStatus("DP-2") == nil)
check("capture empty", model.captureModeStatus("") == nil)

check("pairing expands", model.pairingExpanded(true) == true)
check("pairing collapsed", model.pairingExpanded(false) == false)

local state = model.pairingWindow({
	armed = true,
	pin = "1234",
	pin_pending = true,
	pending = { { uniqueid = "moonlight" } },
})
check("pairing armed", state.armed == true)
check("pairing pin", state.pairingPin == "1234")
check("pairing pinDevices", state.pinDevices[1].uniqueid == "moonlight")
check("pairing pinPending", state.pinPending == true)
local cleared = model.pairingWindow(nil)
check("pairing clear armed", cleared.armed == false)
check("pairing clear pin", cleared.pairingPin == "")
check("pairing clear devices", #cleared.pinDevices == 0)
check("pairing clear pending", cleared.pinPending == false)

check("arm idle", model.showArmRow("idle") == true)
check("arm streaming", model.showArmRow("streaming") == true)
check("arm stopped", model.showArmRow("stopped") == false)

local stopped = model.visibleSections({ state = "stopped", needsYou = false })
check("stopped hides pairing", table.concat(stopped, ",") == "session,devices,display")
check("idle shows pairing", table.concat(model.visibleSections({ state = "idle" }), ","):find("pairing", 1, true) ~= nil)
check("stopped with knock shows pairing", table.concat(model.visibleSections({ state = "stopped", needsYou = true }), ","):find("pairing", 1, true) ~= nil)

local idle = model.sessionFacts({
	state = "idle",
	armed = true,
	summary = { native_paired_clients = 2, version = "0.35.0" },
})
check("idle facts", deepK(idle) == "Devices paired=2|Pairing=open|Host=0.35.0")

local live = model.sessionFacts({
	state = "streaming",
	sessions = 1,
	stream = { width = 1920, height = 1080, fps = 120, bitrate_kbps = 40000, time_to_first_frame_ms = 18 },
})
check("live resolution", live[1].v == "1920 × 1080")
check("live bitrate", live[3].v == "40.0 Mbps")
check("live encode missing", live[4].k == "Encode" and live[4].v == "—")
check("live hdr missing dash", live[5].k == "HDR (verbunden)" and live[5].v == "—")
check("live chroma missing dash", live[6].k == "Chroma (verbunden)" and live[6].v == "—")
check("live first frame", live[7].v == "18 ms")

local liveCodec = model.sessionFacts({
	state = "streaming",
	sessions = 1,
	stream = { width = 1920, height = 1080, fps = 120, bitrate_kbps = 40000, codec = "hevc" },
	statsMeta = { encoder_backend = "nvenc", gpu = "RTX 4090" },
})
check("live encode codec", liveCodec[4].v == "HEVC")
check("live hdr still dashed", liveCodec[5].k == "HDR (verbunden)" and liveCodec[5].v == "—")
check("live chroma still dashed", liveCodec[6].v == "—")
check("live encoder backend", liveCodec[7].k == "Encoder" and liveCodec[7].v == "nvenc · RTX 4090")

local liveEmptyStream = model.sessionFacts({
	state = "streaming",
	sessions = 1,
	stream = nil,
})
check("live nil stream still shows encode", liveEmptyStream[4].k == "Encode" and liveEmptyStream[4].v == "—")
check("live nil stream hdr row", liveEmptyStream[5].k == "HDR (verbunden)" and liveEmptyStream[5].v == "—")
check("live nil stream chroma row", liveEmptyStream[6].k == "Chroma (verbunden)" and liveEmptyStream[6].v == "—")
check("live nil stream bitrate dash", liveEmptyStream[3].v == "—")

check("actions idle empty", #model.sessionActions(false, true) == 0)
local stopOnly = model.sessionActions(true, false)
check("actions stop", #stopOnly == 1 and stopOnly[1].id == "stop")
check("actions end-game", model.sessionActions(true, true)[2].id == "end")

local rows = model.pairingRows(
	true,
	{ { uniqueid = "moonlight", fingerprint = "abc", peer_ip = "192.0.2.1" } },
	{ { id = 3, name = "tv" } }
)
check("pairing row kinds", rows[1].kind == "arm" and rows[2].kind == "pin" and rows[3].kind == "pending")
check("pin device", rows[2].device.uniqueid == "moonlight")
check("pending device", rows[3].device.id == 3)
check("empty pairing rows", #model.pairingRows(false, {}, {}) == 0)

local pin = model.pinArgs("1234", {
	uniqueid = "moonlight",
	fingerprint = "abc",
	peer_ip = "192.0.2.1",
})
check("pinArgs", pin[1] == "pin" and pin[2] == "1234" and pin[3] == "moonlight" and pin[4] == "abc" and pin[5] == "192.0.2.1")
check("pinArgs empty pin", #model.pinArgs("", { uniqueid = "moonlight" }) == 0)
check("pinArgs nil device", #model.pinArgs("1234", nil) == 0)

local display = model.displayRows({ { id = "hotdesk", name = "Hotdesk" } })
check("display dedicated", display[1].kind == "dedicated")
check("display mirror", display[2].kind == "mirror")
check("display preset", display[3].kind == "preset" and display[3].preset.id == "hotdesk")
check("allPresets", #model.allPresets({ { id = "a" } }, { { id = "b" } }) == 2)

check("spark drops nulls", table.concat(model.sparkPoints({ { target = 1 }, { target = nil }, { target = 3 } }, "target"), ",") == "1,3")

check("tabId 0", model.tabId(0) == "overview")
check("tabId 4", model.tabId(4) == "stats")
check("nextTab wrap left", model.nextTab(0, -1) == 4)
check("nextTab wrap right", model.nextTab(4, 1) == 0)
check("tabLabel pair count", model.tabLabel("pair", 2) == "Pair · 2")
check("tabLabel stats", model.tabLabel("stats", 0) == "Stats")

check("incoming empty", model.incomingPair({}) == nil)
check("incoming first", model.incomingPair({ { id = 3 } }).id == 3)
check("remaining rest", model.remainingPair({ { id = 3 }, { id = 4 } })[1].id == 4)

check("policy empty", #model.policyRows({}) == 0)
local policy = model.policyRows({
	topology = "extend",
	identity = "client",
	mode_conflict = "prefer-client",
	max_displays = 2,
})
check("policy topology", policy[1].v == "extend")
check("policy max", policy[4].v == "2")

check("pillars empty", #model.statsPillars({}) == 0)
local pillars = model.statsPillars({
	stream = { bitrate_kbps = 40000, fps = 120 },
	statsSample = { fps = 118.4, stages = { { name = "encode", p99_us = 2321 } } },
	history = { { target = 40, fps = 118.4, encode = 2.321 } },
})
check("pillar target", pillars[1].text == "40.0")
check("pillar fps", pillars[2].text == "118")
check("pillar encode", pillars[3].text == "2.3")
check("encode map stages", model.encodeMs({ stages = { encode = { p99_us = 2000 } } }) == 2)
local zeroBased = {}
zeroBased[0] = { name = "encode", p99_us = 1000 }
check("encode 0-based stages", model.encodeMs({ stages = zeroBased }) == 1)
check("encode missing stages", model.encodeMs({ fps = 120 }) == nil)
check("encode nil sample", model.encodeMs(nil) == nil)
check("chart idle", #model.chartSeries(false) == 1)
check("chart capture encode", model.chartSeries(true)[4].key == "encode")

local streamingNoStream = model.statsPillars({ state = "streaming", sessions = 1 })
check("pillars without stream still encode", streamingNoStream[3].label == "ENCODE" and streamingNoStream[3].text == "—")

local graph = model.graphValues({ 1, 2, 3 })
check("graph normalized lo", graph[1] == 0)
check("graph normalized hi", graph[3] == 1)
check("history window", #model.pushHistory({ 1, 2 }, 3, 2) == 2)
check("hostEnabled desired", model.hostEnabled({ haveDesired = true, desiredRunning = true, state = "stopped" }) == true)
check("hostEnabled from state", model.hostEnabled({ state = "idle" }) == true)
check("needsYou pending", model.needsYou({ pending = 1 }) == true)
check("widget streaming glyph", model.widgetGlyph({ state = "streaming" }) == "cast")
check("widget mismatch glyph", model.widgetGlyph({ pinMismatch = true }) == "alert-triangle")
check("widget error color", model.widgetColor({ pinMismatch = true }) == "error")
check("widget pending color", model.widgetColor({ pending = 1 }) == "error")
check("widget streaming color", model.widgetColor({ state = "streaming" }) == "primary")
check("widget stopped color", model.widgetColor({ state = "stopped" }) == "on_surface_variant")
check("widget badge pending", model.widgetBadge({ pending = 2 }) == "2")
check("widget badge pin", model.widgetBadge({ pinPending = true }) == "1")
check("widget badge idle", model.widgetBadge({ pending = 0 }) == nil)
check("widget pip streaming", model.widgetShowPip({ state = "streaming" }) == true)
check("widget pip idle", model.widgetShowPip({ state = "idle" }) == false)
check("logo first hit", model.widgetLogoPath(function(path) return path == "assets/punktfunk-mark.svg" end) == "assets/punktfunk-mark.svg")
check("logo assets fallback", model.widgetLogoPath(function(path) return path == "punktfunk-mark.svg" end) == "punktfunk-mark.svg")
check("logo miss", model.widgetLogoPath(function() return false end) == nil)
check("logo canonical path", model.MARK_PATH == "assets/punktfunk-mark.svg")
check("panel logo first hit", model.panelLogoPath(function(path) return path == "assets/punktfunk-logo.svg" end) == "assets/punktfunk-logo.svg")
check("panel logo fallback", model.panelLogoPath(function() return false end) == "assets/punktfunk-logo.svg")
check("panel logo size", model.PANEL_LOGO_WIDTH == 140 and model.PANEL_LOGO_HEIGHT == 72)
check("widget mark size", model.WIDGET_MARK_SIZE == 16)
check("widget fill pending", model.widgetFill({ pending = 1 }) == "error/0.22")
check("widget fill streaming", model.widgetFill({ state = "streaming" }) == "primary/0.22")
check("widget border streaming", model.widgetBorder({ state = "streaming" }) == "primary")

check("hero codec streaming", model.heroDetail("streaming", { codec = "hevc" }) == "HEVC · HDR — · —")
check("hero codec idle empty", model.heroDetail("idle", { codec = "hevc" }) == "")
check("hero codec streaming dash", model.heroDetail("streaming", {}) == "— · HDR — · —")
check("hero codec from meta", model.heroDetail("streaming", {}, { codec = "av1" }) == "AV1 · HDR — · —")
check("hero live hdr ja", model.heroDetail("streaming", { codec = "hevc", hdr = true, chroma = "4:4:4" }) == "HEVC · HDR ja · 4:4:4")
check("hero live hdr nein", model.heroDetail("streaming", { codec = "hevc", hdr = false, chroma = "4:2:0" }) == "HEVC · HDR nein · 4:2:0")
check("live hdr from sessions", model.liveHdrText({ hostSessions = { { hdr = true } } }) == "ja")
check("live hdr false", model.liveHdrText({ stream = { hdr = false } }) == "nein")
check("live hdr missing", model.liveHdrText({ stream = { codec = "hevc" } }) == "—")
check("live chroma 444", model.liveChromaText({ stream = { chroma = "444" } }) == "4:4:4")
check("live chroma 420 from stats", model.liveChromaText({ statsMeta = { chroma_subsampling = "4:2:0" } }) == "4:2:0")
check("live chroma missing", model.liveChromaText({}) == "—")
check("policy allow hint next session", model.policyAllowHint():find("nächsten Sitzung", 1, true) ~= nil)
check("policy allow hint client picks", model.policyAllowHint():find("Client wählt", 1, true) ~= nil)
check("encoder empty dash", model.encoderText(nil) == "—")
check("encoder blank dash", model.encoderText({ encoder_backend = "" }) == "—")
check("encoder backend", model.encoderText({ encoder_backend = "vaapi", gpu = "Arc" }) == "vaapi · Arc")
check("hero busy start", model.heroMeta("stopped", "", { hostBusy = true, desiredRunning = true }) == "Starting the host")
check("hero busy stop", model.heroMeta("idle", "", { hostBusy = true, desiredRunning = false }) == "Stopping the host")

check("access native", model.deviceCanAccess({ name = "pad", access_level = "full" }) == true)
check("access moonlight", model.deviceCanAccess({ label = "moon" }) == false)
check("access label", model.accessLabel("controller") == "Controller")
check("access valid", model.isAccessLevel("view") == true)
check("access invalid", model.isAccessLevel("admin") == false)

check("conflict empty", model.conflictBanner({ conflicts = {} }) == nil)
check("conflict one", model.conflictBanner({ conflicts = { "Sunshine (running)" } }) == "Sunshine (running) is also bound on this box")
check("conflict two", model.conflictBanner({ conflicts = { "Sunshine (installed)", "Apollo (running)" } }) == "Sunshine (installed), Apollo (running) are also bound on this box")
check("kept displays", model.keptDisplayCount({ kept_displays = 2 }) == 2)
check("release copy streaming-safe", model.releaseCopy():find("actively streaming", 1, true) ~= nil)

local notifyBody = model.pairingNotifyBody({
	id = 3,
	name = "iPad",
	fingerprint = "0123456789abcdef",
})
check("pairing notify title", model.pairingNotifyTitle() == "Punktfunk pairing request")
check("pairing notify name", notifyBody:find('"iPad" wants to pair', 1, true) ~= nil)
check("pairing notify tail", notifyBody:find("…6789abcdef", 1, true) ~= nil)
check("pairing notify pair tab", notifyBody:find("Pair tab", 1, true) ~= nil)
check("pending id", model.pendingId({ id = 3 }) == "3")
check("pending id missing", model.pendingId({}) == nil)

local fromEvent = model.eventDevice({
	kind = "pairing.pending",
	data = { id = 9, name = "tv", fingerprint = "ffffffffffffffffffaa" },
})
check("event device id", fromEvent.id == "9" and fromEvent.name == "tv")

check(
	"stream start body",
	model.streamStartedBody({ data = { client = "iPad", mode = "exclusive", hdr = true, app = "Desktop" } })
		== "iPad connected · exclusive HDR · Desktop"
)
check("stream stop body", model.streamStoppedBody({ data = { client = "iPad" } }) == "iPad disconnected")
check("stream client fallback", model.streamClient({}, { summary = { client_name = "Couch" } }) == "Couch")
check("host settled after start", model.hostSettled({ hostBusy = true, desiredRunning = true, state = "idle" }) == true)
check("host not settled", model.hostSettled({ hostBusy = true, desiredRunning = true, state = "stopped" }) == false)

if failed > 0 then
	error(string.format("%d model checks failed", failed))
end
print("all model checks passed")
