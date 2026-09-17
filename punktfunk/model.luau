--!nonstrict
-- Phrases, figures, and which sections the panel shows.
-- Pure module: no noctalia globals. plugin_api 22 `require("./model.luau")`.
-- Ported from the Omarchy plugin Model.js (luxus/punktfunk).

local model = {}

model.ACTIVE_PHRASES = {
	"Pushing pixels",
	"Slicing frames",
	"Holding the stream",
	"Guarding the desk",
	"Lighting the couch",
	"Braiding packets",
	"Watching the bitrate",
	"Keeping the latency",
}

model.TAB_NAMES = { "Overview", "Pair", "Devices", "Display", "Stats" }
model.TAB_IDS = { "overview", "pair", "devices", "display", "stats" }
model.ACCESS_LEVELS = { "full", "controller", "view" }
model.ACCESS_LABELS = { full = "Full", controller = "Controller", view = "View" }
-- TODO(bc-e0bdb3f3): `punktfunk-logo.svg` is vendored at both probe paths.
-- Overlay pending badge + state colours around it. Glyph is fallback only.
model.LOGO_PATH = "punktfunk-logo.svg"
model.LOGO_PATHS = {
	"punktfunk-logo.svg",
	"assets/punktfunk-logo.svg",
}

local function toNumber(value, fallback)
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	return n
end

local function wrapIndex(index, n)
	if n <= 0 then
		return 0
	end
	local i = math.floor(toNumber(index, 0))
	return ((i % n) + n) % n
end

function model.mbps(kbps)
	return string.format("%.1f", toNumber(kbps, 0) / 1000)
end

function model.dur(us)
	local n = toNumber(us, 0)
	if n >= 1000 then
		return string.format("%.1f ms", n / 1000)
	end
	return string.format("%d µs", math.floor(n + 0.5))
end

function model.tail(fp)
	local s = tostring(fp or "")
	if s == "" then
		return "—"
	end
	if #s > 10 then
		return "…" .. string.sub(s, -10)
	end
	return s
end

function model.heroPhraseCount(phrases)
	return #(phrases or model.ACTIVE_PHRASES)
end

function model.heroPhrase(index, phrases)
	local list = phrases or model.ACTIVE_PHRASES
	local n = #list
	if n == 0 then
		return ""
	end
	return list[wrapIndex(index, n) + 1]
end

function model.heroTitle(state, clientName)
	if state == "streaming" and clientName and tostring(clientName) ~= "" then
		return tostring(clientName)
	end
	return "Punktfunk"
end

function model.heroMeta(state, phrase, snap)
	local s = snap or {}
	if s.hostBusy == true then
		if s.desiredRunning == true then
			return "Starting the host"
		end
		return "Stopping the host"
	end
	if state == "streaming" then
		return tostring(phrase or "")
	end
	if state == "idle" then
		return "Ready to stream"
	end
	return "Host is stopped"
end

function model.heroCodec(stream)
	if type(stream) ~= "table" then
		return ""
	end
	local codec = stream.codec
	if codec == nil or tostring(codec) == "" then
		return ""
	end
	return string.upper(tostring(codec))
end

function model.heroDetail(state, stream)
	if state ~= "streaming" then
		return ""
	end
	return model.heroCodec(stream)
end

function model.captureModeStatus(output)
	local mode = string.gsub(tostring(output or ""), "^%s+", "")
	mode = string.gsub(mode, "%s+$", "")
	if mode == "dedicated" or mode == "mirror" then
		return mode
	end
	return nil
end

function model.sessionLive(state, sessions, games)
	local gameCount = 0
	if type(games) == "table" then
		gameCount = #games
	end
	return state == "streaming" or toNumber(sessions, 0) > 0 or gameCount > 0
end

function model.showArmRow(state)
	return state == "idle" or state == "streaming"
end

function model.pairingExpanded(needsYou)
	return not not needsYou
end

function model.pairingWindow(data)
	local d = data or {}
	local devices = d.pending or {}
	local pinPending = (d.pin_pending == true) and #devices > 0
	return {
		armed = d.armed == true,
		pairingPin = d.pin or "",
		pinDevices = devices,
		pinPending = pinPending,
	}
end

function model.sectionVisible(section, snap)
	local s = snap or {}
	if section == "session" then
		return true
	end
	if section == "pairing" then
		return model.showArmRow(s.state) or s.needsYou == true
	end
	if section == "devices" then
		return true
	end
	if section == "display" then
		return true
	end
	return false
end

function model.visibleSections(snap)
	local names = { "session", "pairing", "devices", "display" }
	local out = {}
	for _, name in ipairs(names) do
		if model.sectionVisible(name, snap) then
			table.insert(out, name)
		end
	end
	return out
end

function model.sessionFacts(snap)
	local s = snap or {}
	local stream = s.stream
	local summary = s.summary or {}
	if s.state == "stopped" then
		return {}
	end
	if model.sessionLive(s.state, s.sessions, s.games) and type(stream) == "table" then
		local out = {
			{ k = "Resolution", v = tostring(stream.width) .. " × " .. tostring(stream.height) },
			{ k = "Frame rate", v = tostring(stream.fps) .. " fps" },
			{ k = "Bitrate", v = model.mbps(stream.bitrate_kbps) .. " Mbps" },
		}
		if toNumber(stream.time_to_first_frame_ms, 0) > 0 then
			table.insert(out, { k = "First frame", v = tostring(stream.time_to_first_frame_ms) .. " ms" })
		end
		return out
	end
	local pairing = "closed"
	if s.armed then
		pairing = "open"
	end
	return {
		{ k = "Devices paired", v = tostring(summary.native_paired_clients or 0) },
		{ k = "Pairing", v = pairing },
		{ k = "Host", v = summary.version or "—" },
	}
end

function model.sessionActions(live, hasGame)
	if not live then
		return {}
	end
	local out = { { id = "stop", label = "Stop the session" } }
	if hasGame then
		table.insert(out, { id = "end", label = "End the game" })
	end
	return out
end

function model.pairingRows(arm, pinDevices, pendingDevices)
	local out = {}
	if arm then
		table.insert(out, { kind = "arm" })
	end
	for _, device in ipairs(pinDevices or {}) do
		table.insert(out, { kind = "pin", device = device })
	end
	for _, device in ipairs(pendingDevices or {}) do
		table.insert(out, { kind = "pending", device = device })
	end
	return out
end

function model.pinArgs(pin, device)
	local d = device or {}
	local values = {
		string.gsub(tostring(pin or ""), "^%s+", ""),
		string.gsub(tostring(d.uniqueid or ""), "^%s+", ""),
		string.gsub(tostring(d.fingerprint or ""), "^%s+", ""),
		string.gsub(tostring(d.peer_ip or ""), "^%s+", ""),
	}
	for i = 1, #values do
		values[i] = string.gsub(values[i], "%s+$", "")
		if values[i] == "" then
			return {}
		end
	end
	return { "pin", values[1], values[2], values[3], values[4] }
end

function model.displayRows(presets)
	local out = {
		{ kind = "dedicated", label = "Dedicated display", detail = "Stream a virtual display at the client's size" },
		{ kind = "mirror", label = "This screen", detail = "Stream the primary monitor on this box" },
	}
	for _, preset in ipairs(presets or {}) do
		table.insert(out, { kind = "preset", preset = preset })
	end
	return out
end

function model.allPresets(builtIn, custom)
	local out = {}
	for _, preset in ipairs(builtIn or {}) do
		table.insert(out, preset)
	end
	for _, preset in ipairs(custom or {}) do
		table.insert(out, preset)
	end
	return out
end

function model.sparkPoints(history, key)
	local out = {}
	for _, row in ipairs(history or {}) do
		if type(row) == "table" then
			local v = row[key]
			if v ~= nil then
				table.insert(out, tonumber(v) or 0)
			end
		end
	end
	return out
end

function model.tabId(index)
	local i = math.floor(toNumber(index, 0))
	if i < 0 or i >= #model.TAB_IDS then
		return model.TAB_IDS[1]
	end
	return model.TAB_IDS[i + 1]
end

function model.tabIndex(id)
	local wanted = tostring(id or "")
	for i, name in ipairs(model.TAB_IDS) do
		if name == wanted then
			return i - 1
		end
	end
	return 0
end

function model.nextTab(index, delta)
	local n = #model.TAB_IDS
	local i = toNumber(index, 0)
	local d = toNumber(delta, 0)
	return (i + (d % n) + n) % n
end

function model.tabLabel(id, pending)
	if id == "pair" and toNumber(pending, 0) > 0 then
		return "Pair · " .. tostring(toNumber(pending, 0))
	end
	return model.TAB_NAMES[model.tabIndex(id) + 1]
end

function model.incomingPair(pendingDevices)
	local list = pendingDevices or {}
	if #list > 0 then
		return list[1]
	end
	return nil
end

function model.remainingPair(pendingDevices)
	local list = pendingDevices or {}
	if #list > 1 then
		local out = {}
		for i = 2, #list do
			table.insert(out, list[i])
		end
		return out
	end
	return {}
end

function model.policyRows(effective)
	local e = effective or {}
	if not e.topology then
		return {}
	end
	return {
		{ k = "Topology", v = tostring(e.topology) },
		{ k = "Identity", v = tostring(e.identity or "—") },
		{ k = "Mode clash", v = tostring(e.mode_conflict or "—") },
		{ k = "Max displays", v = tostring(e.max_displays or "—") },
	}
end

function model.chartSeries(captureArmed)
	local out = { { key = "target", label = "Target", unit = "Mbps", digits = 1 } }
	if captureArmed then
		table.insert(out, { key = "sent", label = "Sent", unit = "Mbps", digits = 1 })
		table.insert(out, { key = "fps", label = "New frames", unit = "fps", digits = 1 })
		table.insert(out, { key = "encode", label = "Encode p99", unit = "ms", digits = 1 })
	end
	return out
end

function model.seriesLast(pts)
	local list = pts or {}
	for i = #list, 1, -1 do
		if list[i] ~= nil then
			return tonumber(list[i])
		end
	end
	return nil
end

function model.pillarMeter(history, key, current)
	if current == nil then
		return 0
	end
	local pts = model.sparkPoints(history, key)
	local hi = toNumber(current, 0)
	for _, v in ipairs(pts) do
		if v > hi then
			hi = v
		end
	end
	if hi <= 0 then
		return 0
	end
	local ratio = toNumber(current, 0) / hi
	if ratio < 0 then
		return 0
	end
	if ratio > 1 then
		return 1
	end
	return ratio
end

function model.encodeMs(statsSample)
	local stages = statsSample and statsSample.stages or {}
	for _, stage in ipairs(stages) do
		if type(stage) == "table" and stage.name == "encode" then
			return toNumber(stage.p99_us, 0) / 1000
		end
	end
	return nil
end

function model.statsPillars(snap)
	local s = snap or {}
	local stream = s.stream
	if type(stream) ~= "table" then
		return {}
	end
	local target = toNumber(stream.bitrate_kbps, 0) / 1000
	local fps = nil
	if type(s.statsSample) == "table" and s.statsSample.fps ~= nil then
		fps = toNumber(s.statsSample.fps, 0)
	else
		fps = toNumber(stream.fps, 0)
	end
	local encode = model.encodeMs(s.statsSample)
	local history = s.history or {}
	local fpsText = "—"
	if fps and fps ~= 0 then
		fpsText = tostring(math.floor(fps + 0.5))
	end
	local encodeText = "—"
	if encode ~= nil then
		encodeText = string.format("%.1f", encode)
	end
	local fpsNote = "no sample yet"
	if stream.fps then
		fpsNote = tostring(stream.fps) .. " fps mode"
	end
	local encodeNote = "record timings to sample"
	if encode ~= nil then
		encodeNote = "p99 ms"
	end
	return {
		{
			label = "TARGET",
			text = string.format("%.1f", target),
			note = "Mbps encoder target",
			meter = model.pillarMeter(history, "target", target),
		},
		{
			label = "FRAMES",
			text = fpsText,
			note = fpsNote,
			meter = model.pillarMeter(history, "fps", fps),
		},
		{
			label = "ENCODE",
			text = encodeText,
			note = encodeNote,
			meter = model.pillarMeter(history, "encode", encode),
		},
	}
end

function model.graphValues(pts)
	local list = pts or {}
	if #list == 0 then
		return {}
	end
	local lo = list[1]
	local hi = list[1]
	for _, v in ipairs(list) do
		if v < lo then
			lo = v
		end
		if v > hi then
			hi = v
		end
	end
	if hi - lo < 1e-6 then
		lo = lo - 1
		hi = hi + 1
	end
	local out = {}
	for _, v in ipairs(list) do
		table.insert(out, (v - lo) / (hi - lo))
	end
	return out
end

function model.concatDevices(nativeClients, gamestreamClients)
	local out = {}
	for _, device in ipairs(nativeClients or {}) do
		table.insert(out, device)
	end
	for _, device in ipairs(gamestreamClients or {}) do
		table.insert(out, device)
	end
	return out
end

function model.devicePlane(device)
	if type(device) ~= "table" then
		return "moonlight"
	end
	if device.access_level ~= nil or device.name ~= nil then
		return "punktfunk"
	end
	return "moonlight"
end

function model.deviceTitle(device)
	if type(device) ~= "table" then
		return "(unnamed device)"
	end
	local title = device.name or device.label
	if title and tostring(title) ~= "" then
		return tostring(title)
	end
	return "(unnamed device)"
end

function model.historyPoint(stream, statsSample)
	local p = { target = nil, sent = nil, fps = nil, encode = nil }
	if type(stream) == "table" then
		p.target = toNumber(stream.bitrate_kbps, 0) / 1000
	end
	if type(statsSample) == "table" then
		p.sent = toNumber(statsSample.mbps, 0)
		p.fps = toNumber(statsSample.fps, 0)
		p.encode = model.encodeMs(statsSample)
	end
	return p
end

function model.pushHistory(history, point, historyMax)
	local maxCount = historyMax or 90
	local out = {}
	for _, row in ipairs(history or {}) do
		table.insert(out, row)
	end
	table.insert(out, point)
	if #out > maxCount then
		local trimmed = {}
		for i = #out - maxCount + 1, #out do
			table.insert(trimmed, out[i])
		end
		return trimmed
	end
	return out
end

function model.defaultSnap()
	return {
		state = "stopped",
		sessions = 0,
		pending = 0,
		pinPending = false,
		armed = false,
		pairingPin = "",
		pinDevices = {},
		pendingDevices = {},
		nativeClients = {},
		gamestreamClients = {},
		games = {},
		displayPreset = "",
		displayEffective = {},
		displayPresets = {},
		customPresets = {},
		captureMode = "dedicated",
		summary = {},
		stream = nil,
		sessionMode = nil,
		audioStreaming = false,
		captureArmed = false,
		captureSamples = 0,
		statsSample = nil,
		statsMeta = nil,
		history = {},
		pinMismatch = false,
		lastError = "",
		hostEnabled = false,
		haveDesired = false,
		desiredRunning = false,
		hostBusy = false,
	}
end

function model.hostEnabled(snap)
	local s = snap or {}
	if s.haveDesired then
		return s.desiredRunning == true
	end
	return s.state ~= "stopped"
end

function model.needsYou(snap)
	local s = snap or {}
	return toNumber(s.pending, 0) > 0 or s.pinPending == true
end

function model.widgetGlyph(snap)
	local s = snap or {}
	if s.pinMismatch then
		return "alert-triangle"
	end
	if s.state == "streaming" then
		return "cast"
	end
	if s.state == "idle" then
		return "cast"
	end
	return "cast-off"
end

function model.widgetColor(snap)
	local s = snap or {}
	if s.pinMismatch or model.needsYou(s) then
		return "error"
	end
	if s.state == "streaming" then
		return "primary"
	end
	if s.state == "stopped" then
		return "on_surface_variant"
	end
	return "on_surface"
end

-- Fill/border drawn *around* the logo. Never tints or replaces the SVG.
function model.widgetFill(snap)
	local s = snap or {}
	if s.pinMismatch or model.needsYou(s) then
		return "error/0.22"
	end
	if s.state == "streaming" then
		return "primary/0.22"
	end
	return nil
end

function model.widgetBorder(snap)
	return model.widgetColor(snap)
end

function model.widgetLogoPath(fileExists)
	if type(fileExists) ~= "function" then
		return nil
	end
	for _, rel in ipairs(model.LOGO_PATHS) do
		if fileExists(rel) then
			return rel
		end
	end
	return nil
end

-- Count for the bar pending badge. Pin-pending Moonlight is needsYou but has
-- no native pending id, so the badge still shows as 1.
function model.widgetBadge(snap)
	local s = snap or {}
	local pending = toNumber(s.pending, 0)
	if pending > 0 then
		return tostring(pending)
	end
	if s.pinPending == true then
		return "1"
	end
	return nil
end

function model.widgetShowPip(snap)
	local s = snap or {}
	return s.state == "streaming"
end

function model.deviceCanAccess(device)
	return model.devicePlane(device) == "punktfunk"
end

function model.accessLabel(level)
	local key = tostring(level or "")
	return model.ACCESS_LABELS[key] or key
end

function model.isAccessLevel(level)
	local wanted = tostring(level or "")
	for _, name in ipairs(model.ACCESS_LEVELS) do
		if name == wanted then
			return true
		end
	end
	return false
end

function model.conflictLabels(summary)
	local list = type(summary) == "table" and summary.conflicts or nil
	if type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, item in ipairs(list) do
		if type(item) == "string" then
			local trimmed = string.gsub(item, "^%s+", "")
			trimmed = string.gsub(trimmed, "%s+$", "")
			if trimmed ~= "" then
				table.insert(out, trimmed)
			end
		elseif type(item) == "table" then
			local label = item.label or item.name or item.app
			if label and tostring(label) ~= "" then
				table.insert(out, tostring(label))
			end
		end
	end
	return out
end

function model.conflictBanner(summary)
	local labels = model.conflictLabels(summary)
	if #labels == 0 then
		return nil
	end
	if #labels == 1 then
		return labels[1] .. " is also bound on this box"
	end
	return table.concat(labels, ", ") .. " are also bound on this box"
end

function model.keptDisplayCount(summary)
	local s = summary or {}
	return toNumber(s.kept_displays, 0)
end

function model.releaseCopy()
	return "Release kept virtual heads so physical screens come back. Never touches a display that is actively streaming."
end

function model.pairingNotifyTitle()
	return "Punktfunk pairing request"
end

function model.deviceNotifyName(device)
	if type(device) ~= "table" then
		return "a device"
	end
	local name = device.name or device.label or device.client_name
	if name and tostring(name) ~= "" then
		return tostring(name)
	end
	return "a device"
end

function model.pairingNotifyBody(device)
	local name = model.deviceNotifyName(device)
	local body = '"' .. name .. '" wants to pair'
	local fp = type(device) == "table" and (device.fingerprint or device.device_fingerprint) or nil
	local tail = model.tail(fp)
	if tail ~= "—" then
		body = body .. " · " .. tail
	end
	return body .. " — open the Pair tab to Accept or Reject"
end

function model.pendingId(device)
	if type(device) ~= "table" or device.id == nil then
		return nil
	end
	local id = tostring(device.id)
	if id == "" then
		return nil
	end
	return id
end

local function eventTables(ev)
	local out = {}
	if type(ev) == "table" then
		table.insert(out, ev)
		if type(ev.data) == "table" then
			table.insert(out, ev.data)
		end
		if type(ev.stream) == "table" then
			table.insert(out, ev.stream)
		end
		if type(ev.data) == "table" and type(ev.data.stream) == "table" then
			table.insert(out, ev.data.stream)
		end
		if type(ev.device) == "table" then
			table.insert(out, ev.device)
		end
		if type(ev.data) == "table" and type(ev.data.device) == "table" then
			table.insert(out, ev.data.device)
		end
	end
	return out
end

local function firstString(tables, keys)
	for _, obj in ipairs(tables) do
		for _, key in ipairs(keys) do
			local value = obj[key]
			local kind = type(value)
			if kind == "string" then
				local trimmed = string.gsub(value, "^%s+", "")
				trimmed = string.gsub(trimmed, "%s+$", "")
				if trimmed ~= "" then
					return trimmed
				end
			elseif kind == "number" then
				return tostring(value)
			end
		end
	end
	return nil
end

function model.eventDevice(ev)
	local tables = eventTables(ev)
	if #tables == 0 then
		return nil
	end
	local device = {}
	device.id = firstString(tables, { "id", "device_id", "pending_id" })
	device.name = firstString(tables, { "name", "device_name", "client_name", "label" })
	device.fingerprint = firstString(tables, { "fingerprint", "device_fingerprint" })
	if device.id == nil and device.name == nil and device.fingerprint == nil then
		return nil
	end
	return device
end

function model.streamClient(ev, snap)
	local tables = eventTables(ev)
	local client = firstString(tables, { "client", "client_name", "device_name", "name" })
	if client then
		return client
	end
	local summary = type(snap) == "table" and snap.summary or nil
	if type(summary) == "table" and summary.client_name and tostring(summary.client_name) ~= "" then
		return tostring(summary.client_name)
	end
	return "a client"
end

function model.streamStartedBody(ev, snap)
	local client = model.streamClient(ev, snap)
	local body = client .. " connected"
	local tables = eventTables(ev)
	local mode = firstString(tables, { "mode", "session_mode", "session" })
	if mode then
		body = body .. " · " .. mode
	end
	local hdr = false
	for _, obj in ipairs(tables) do
		if obj.hdr == true or obj.hdr == "true" then
			hdr = true
		end
	end
	if hdr then
		body = body .. " HDR"
	end
	local app = firstString(tables, { "app", "title", "game" })
	if app then
		body = body .. " · " .. app
	end
	return body
end

function model.streamStoppedBody(ev, snap)
	return model.streamClient(ev, snap) .. " disconnected"
end

function model.hostSettled(snap)
	local s = snap or {}
	if s.hostBusy ~= true then
		return true
	end
	if s.desiredRunning == true then
		return s.state == "idle" or s.state == "streaming"
	end
	return s.state == "stopped"
end

return model
