--!nonstrict
-- The plugin's data half: one `ctl watch`, the snapshots it triggers, and the
-- only spawn site. Luau holds no credential and speaks no HTTPS — every host
-- call is `punktfunk-host ctl` (plugin_api 24 argv form), which pins the
-- certificate before sending the operator token.

local model
local ctl

local function loadModule(path, fallback)
	local ok, result = pcall(require, path)
	if ok and type(result) == "table" then
		return result
	end
	if type(noctalia) == "table" and type(noctalia.log) == "function" then
		noctalia.log("Punktfunk: require(" .. path .. ") failed: " .. tostring(result))
	end
	return fallback
end

model = loadModule("./model.luau", {
	defaultSnap = function()
		return { state = "stopped", pending = 0, history = {}, summary = {}, games = {}, nativeClients = {}, gamestreamClients = {}, pinDevices = {}, pendingDevices = {} }
	end,
	pairingWindow = function()
		return { armed = false, pairingPin = "", pinDevices = {}, pinPending = false }
	end,
	historyPoint = function()
		return { target = nil, sent = nil, fps = nil, encode = nil }
	end,
	pushHistory = function(history, point)
		local out = {}
		for _, row in ipairs(history or {}) do
			table.insert(out, row)
		end
		table.insert(out, point)
		return out
	end,
	pinArgs = function()
		return {}
	end,
	hostEnabled = function(snap)
		return type(snap) == "table" and snap.state ~= "stopped"
	end,
	pairingNotifyTitle = function()
		return "Punktfunk pairing request"
	end,
	pairingNotifyBody = function(device)
		local name = "(unnamed device)"
		if type(device) == "table" and device.name and device.name ~= "" then
			name = tostring(device.name)
		end
		return '"' .. name .. '" wants to pair — open the Pair tab to Accept or Reject'
	end,
	pendingId = function(device)
		if type(device) == "table" and device.id ~= nil then
			return tostring(device.id)
		end
		return nil
	end,
	eventDevice = function()
		return nil
	end,
	streamStartedBody = function()
		return "a client connected"
	end,
	streamStoppedBody = function()
		return "a client disconnected"
	end,
	hostSettled = function()
		return true
	end,
	isAccessLevel = function()
		return false
	end,
})

ctl = loadModule("./ctl.luau", {
	hostArgv = function(args)
		local argv = { "punktfunk-host", "ctl" }
		for _, arg in ipairs(args or {}) do
			table.insert(argv, arg)
		end
		return argv
	end,
	jsonArgv = function(args)
		local argv = { "punktfunk-host", "ctl" }
		for _, arg in ipairs(args or {}) do
			table.insert(argv, arg)
		end
		table.insert(argv, "--json")
		return argv
	end,
	watchCommand = function()
		return "punktfunk-host ctl watch --kinds 'pairing.*,stream.*,session.*,host.*'"
	end,
	watchNeedles = function()
		return { "punktfunk-host", "watch" }
	end,
	interpret = function()
		return nil, { message = "ctl module missing" }
	end,
	isPinMismatch = function()
		return false
	end,
	EXIT_PIN = 4,
	HISTORY_MAX = 90,
	WATCH_RETRY_MS = 15000,
	STATS_POLL_MS = 2000,
	HOST_SETTLE_MS = 1500,
	systemctlArgv = function(action)
		return { "systemctl", "--user", action, "punktfunk-host.service" }
	end,
	listMonitorsArgv = function()
		return { "punktfunk-host", "list-monitors" }
	end,
	displaySettingsPath = function()
		return "~/.config/punktfunk/display-settings.json"
	end,
	hostEnvPath = function()
		return "~/.config/punktfunk/host.env"
	end,
	captureModeFromConfig = function()
		return "dedicated"
	end,
	applyCaptureMonitor = function(settings, connector)
		local data = settings or {}
		data.capture_monitor = connector
		return data
	end,
	stripCapturePin = function(text)
		return text or ""
	end,
	primaryConnector = function()
		return nil
	end,
	consoleUrlFromOutput = function()
		return "https://localhost:47992"
	end,
	xdgOpenArgv = function(url)
		return { "xdg-open", url }
	end,
	shouldPollStats = function()
		return false
	end,
	eventKind = function()
		return nil
	end,
	eventClearsHistory = function()
		return false
	end,
	eventStopsHost = function()
		return false
	end,
	eventNeedsClients = function()
		return false
	end,
	eventIsPairingPending = function()
		return false
	end,
	eventIsStreamStart = function()
		return false
	end,
	eventIsStreamStop = function()
		return false
	end,
	isAccessLevel = function()
		return false
	end,
	hostEnvHasCapturePin = function()
		return false
	end,
})

local snap = model.defaultSnap()
local lastRequestT = 0
local notifiedPending = {}
local watcherStarted = false
local retryAt = 0
local lastStatsAt = 0
local settleUntil = 0
local verifyWatcher

local function nowMs()
	if type(noctalia.nowMs) == "function" then
		return noctalia.nowMs()
	end
	return os.time() * 1000
end

local function configHome()
	if type(noctalia.getenv) == "function" then
		local xdg = noctalia.getenv("XDG_CONFIG_HOME")
		if type(xdg) == "string" and xdg ~= "" then
			return xdg
		end
	end
	if type(noctalia.expandPath) == "function" then
		return noctalia.expandPath("~/.config")
	end
	return (noctalia.getenv("HOME") or "") .. "/.config"
end

local function decodeJson(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	if type(noctalia.json) ~= "table" or type(noctalia.json.decode) ~= "function" then
		return nil
	end
	local parsed = noctalia.json.decode(raw)
	if type(parsed) == "table" then
		return parsed
	end
	return nil
end

local function encodeJson(value)
	if type(noctalia.json) ~= "table" or type(noctalia.json.encode) ~= "function" then
		return nil
	end
	return noctalia.json.encode(value, true)
end

local function publish()
	snap.hostEnabled = model.hostEnabled(snap)
	noctalia.state.set("snap", snap)
end

local function openPairTab()
	noctalia.state.set("focusPair", {
		t = nowMs(),
		reason = "pairing",
	})
end

local function pruneNotified(devices)
	local live = {}
	for _, device in ipairs(devices or {}) do
		local id = model.pendingId(device)
		if id then
			live[id] = true
		end
	end
	for id in pairs(notifiedPending) do
		if not live[id] then
			notifiedPending[id] = nil
		end
	end
end

-- noctalia.notify is title+body only (plugin_api 24). Approve/Deny stay on
-- the Pair tab, keyed by pending id so two knocks cannot share a toast.
local function toastPending(devices)
	local any = false
	for _, device in ipairs(devices or {}) do
		local id = model.pendingId(device)
		if id and not notifiedPending[id] then
			notifiedPending[id] = true
			any = true
			if type(noctalia.notify) == "function" then
				noctalia.notify(model.pairingNotifyTitle(), model.pairingNotifyBody(device))
			end
		end
	end
	if any then
		openPairTab()
	end
end

local function applyPairingWindow(data)
	local nextState = model.pairingWindow(data)
	snap.armed = nextState.armed
	snap.pairingPin = nextState.pairingPin
	snap.pinDevices = nextState.pinDevices
	snap.pinPending = nextState.pinPending
end

local function clearPairingState()
	applyPairingWindow(nil)
	snap.pendingDevices = {}
	snap.pending = 0
end

local function markStopped()
	snap.state = "stopped"
	snap.sessions = 0
	snap.stream = nil
	if snap.hostBusy == true and snap.desiredRunning == false then
		snap.hostBusy = false
		snap.haveDesired = false
	elseif not (snap.haveDesired and snap.desiredRunning) then
		snap.haveDesired = false
	end
end

local function runJson(args, callback)
	if type(noctalia.runAsync) ~= "function" then
		if callback then
			callback(nil, { message = "noctalia.runAsync is missing" })
		end
		return
	end
	noctalia.runAsync(ctl.jsonArgv(args), function(result)
		result = result or {}
		local decoded = decodeJson(result.stdout)
		local data, err = ctl.interpret(decoded, result.exitCode, result.stdout)
		if err then
			snap.lastError = err.message or ""
			if ctl.isPinMismatch(err) then
				snap.pinMismatch = true
			end
			publish()
			if callback then
				callback(nil, err)
			end
			return
		end
		snap.pinMismatch = false
		snap.lastError = ""
		if callback then
			callback(data, nil)
		end
	end)
end

local function runArgv(argv, callback)
	noctalia.runAsync(argv, function(result)
		result = result or {}
		if result.exitCode == 0 then
			snap.lastError = ""
			if callback then
				callback(result.stdout, nil)
			end
		else
			local message = noctalia.string and noctalia.string.trim and noctalia.string.trim(result.stderr or "") or (result.stderr or "")
			if message == "" then
				message = "command exited with code " .. tostring(result.exitCode)
			end
			snap.lastError = message
			publish()
			if callback then
				callback(nil, { code = result.exitCode, message = message })
			end
		end
	end)
end

local function refreshStatus()
	runJson({ "status" }, function(data, err)
		if err then
			markStopped()
			publish()
			return
		end
		data = data or {}
		if snap.hostBusy ~= true then
			snap.haveDesired = false
		end
		snap.sessions = data.active_sessions or 0
		snap.games = data.games or {}
		if snap.sessions > 0 then
			snap.state = "streaming"
		else
			snap.state = "idle"
		end
		snap.stream = data.stream
		snap.audioStreaming = data.audio_streaming == true
		if model.hostSettled(snap) then
			snap.hostBusy = false
			snap.haveDesired = false
		end
		publish()
	end)
end

local function refreshPending()
	runJson({ "pending" }, function(data, err)
		if err then
			snap.pendingDevices = {}
			snap.pending = 0
			pruneNotified({})
		else
			snap.pendingDevices = data or {}
			snap.pending = #snap.pendingDevices
			pruneNotified(snap.pendingDevices)
			toastPending(snap.pendingDevices)
		end
		publish()
	end)
end

local function refreshPairStatus()
	runJson({ "pair", "status" }, function(data, err)
		if err or type(data) ~= "table" then
			applyPairingWindow(nil)
		else
			applyPairingWindow(data)
		end
		publish()
	end)
end

local function refreshSummary()
	runJson({ "summary" }, function(data, err)
		if err then
			snap.summary = {}
		else
			snap.summary = data or {}
		end
		publish()
	end)
end

local function refreshClients()
	runJson({ "clients" }, function(data, err)
		if err or type(data) ~= "table" then
			return
		end
		snap.nativeClients = data.native or {}
		snap.gamestreamClients = data.gamestream or {}
		publish()
	end)
end

local function readCaptureMode()
	local settingsRaw = noctalia.readFile(ctl.displaySettingsPath(configHome()))
	local envRaw = noctalia.readFile(ctl.hostEnvPath(configHome()))
	local settings = decodeJson(settingsRaw) or {}
	snap.captureMode = ctl.captureModeFromConfig(settings, envRaw)
end

local function refreshDisplays()
	readCaptureMode()
	runJson({ "display" }, function(data, err)
		if err or type(data) ~= "table" then
			publish()
			return
		end
		snap.displayPreset = (data.settings and data.settings.preset) or ""
		snap.displayEffective = data.effective or {}
		snap.displayPresets = data.presets or {}
		snap.customPresets = data.custom_presets or {}
		publish()
	end)
end

local function refreshStats()
	runJson({ "stats" }, function(data, err)
		if err or type(data) ~= "table" then
			return
		end
		snap.stream = data.stream
		snap.sessionMode = data.session
		snap.captureArmed = type(data.capture) == "table" and data.capture.armed == true
		snap.captureSamples = (type(data.capture) == "table" and data.capture.sample_count) or 0
		snap.statsSample = data.sample
		snap.statsMeta = data.meta
		snap.history = model.pushHistory(snap.history, model.historyPoint(snap.stream, snap.statsSample), ctl.HISTORY_MAX)
		publish()
	end)
end

local function refresh()
	refreshStatus()
	refreshSummary()
	refreshPending()
	refreshPairStatus()
end

local function refreshAll()
	refresh()
	refreshClients()
	refreshDisplays()
end

local function setHostEnabled(on)
	snap.haveDesired = true
	snap.desiredRunning = on == true
	snap.hostBusy = true
	settleUntil = nowMs() + (ctl.HOST_SETTLE_MS or 1500)
	publish()
	noctalia.runAsync(ctl.systemctlArgv(on and "start" or "stop"))
end

local function setCaptureMode(mode)
	if mode ~= "dedicated" and mode ~= "mirror" then
		return
	end
	local settingsPath = ctl.displaySettingsPath(configHome())
	local envPath = ctl.hostEnvPath(configHome())
	local settings = decodeJson(noctalia.readFile(settingsPath)) or {}
	if mode == "dedicated" then
		local nextSettings = ctl.applyCaptureMonitor(settings, nil)
		local encoded = encodeJson(nextSettings)
		if encoded then
			noctalia.writeFile(settingsPath, encoded)
		end
		local envRaw = noctalia.readFile(envPath)
		if type(envRaw) == "string" and envRaw ~= "" then
			noctalia.writeFile(envPath, ctl.stripCapturePin(envRaw))
		end
		snap.captureMode = "dedicated"
		publish()
		noctalia.runAsync(ctl.systemctlArgv("try-restart"))
		return
	end
	runArgv(ctl.listMonitorsArgv(), function(output, err)
		if err then
			snap.lastError = "Couldn't list the screens. Run this from the desktop session."
			publish()
			return
		end
		local conn = ctl.primaryConnector(output)
		if not conn then
			snap.lastError = "Couldn't pick a screen to mirror. This box has no primary display."
			publish()
			return
		end
		local nextSettings = ctl.applyCaptureMonitor(settings, conn)
		local encoded = encodeJson(nextSettings)
		if encoded then
			noctalia.writeFile(settingsPath, encoded)
		end
		local envRaw = noctalia.readFile(envPath)
		if type(envRaw) == "string" and envRaw ~= "" then
			noctalia.writeFile(envPath, ctl.stripCapturePin(envRaw))
		end
		snap.captureMode = "mirror"
		publish()
		noctalia.runAsync(ctl.systemctlArgv("try-restart"))
	end)
end

local function openConsole()
	runArgv(ctl.hostArgv and ctl.hostArgv({ "console-url" }) or { "punktfunk-host", "ctl", "console-url" }, function(output, err)
		local url = ctl.consoleUrlFromOutput(output, err and err.code or 0)
		if err then
			url = ctl.consoleUrlFromOutput("", 1)
		end
		noctalia.runAsync(ctl.xdgOpenArgv(url))
	end)
end

local function handleRequest(req)
	local op = req.op
	if op == "refresh" then
		refresh()
	elseif op == "refresh-all" then
		refreshAll()
		retryAt = 0
		verifyWatcher()
	elseif op == "refresh-stats" then
		refreshStats()
	elseif op == "refresh-clients" then
		refreshClients()
	elseif op == "refresh-displays" then
		refreshDisplays()
	elseif op == "approve" then
		runJson({ "approve", tostring(req.id or "") }, function()
			refresh()
			refreshClients()
		end)
	elseif op == "deny" then
		runJson({ "deny", tostring(req.id or "") }, function()
			refresh()
		end)
	elseif op == "pin" then
		local args = model.pinArgs(req.pin, {
			uniqueid = req.uniqueid,
			fingerprint = req.fingerprint,
			peer_ip = req.peer_ip,
		})
		if #args == 0 then
			snap.lastError = "Moonlight PIN needs the PIN, unique id, fingerprint, and peer IP."
			publish()
			return
		end
		runJson(args, function()
			refresh()
		end)
	elseif op == "unpair" then
		runJson({ "unpair", tostring(req.fingerprint or "") }, function()
			refresh()
			refreshClients()
		end)
	elseif op == "access" then
		local level = tostring(req.level or "")
		if not ((ctl.isAccessLevel and ctl.isAccessLevel(level)) or (model.isAccessLevel and model.isAccessLevel(level))) then
			snap.lastError = "Access level must be full, controller, or view."
			publish()
			return
		end
		local fingerprint = tostring(req.fingerprint or "")
		if fingerprint == "" then
			snap.lastError = "Access needs a device fingerprint."
			publish()
			return
		end
		runJson({ "access", fingerprint, level }, function()
			refreshClients()
		end)
	elseif op == "rename" then
		local fingerprint = tostring(req.fingerprint or "")
		local name = tostring(req.name or "")
		name = string.gsub(name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")
		if fingerprint == "" or name == "" then
			snap.lastError = "Rename needs a fingerprint and a name."
			publish()
			return
		end
		runJson({ "rename", fingerprint, name }, function()
			refreshClients()
		end)
	elseif op == "display-release" then
		runJson({ "display", "release" }, function()
			refreshDisplays()
			refreshSummary()
		end)
	elseif op == "pair-arm" then
		runJson({ "pair", "arm" }, function()
			refresh()
		end)
	elseif op == "pair-disarm" then
		runJson({ "pair", "disarm" }, function()
			refresh()
		end)
	elseif op == "stop-session" then
		runJson({ "stop-session" }, function()
			refresh()
		end)
	elseif op == "end-game" then
		runJson({ "end-game" }, function()
			refresh()
		end)
	elseif op == "display-preset" then
		runJson({ "display", "preset", tostring(req.id or "") }, function()
			refreshDisplays()
		end)
	elseif op == "capture-mode" then
		setCaptureMode(req.mode)
	elseif op == "capture-start" then
		runJson({ "stats", "record", "start" }, function()
			refreshStats()
		end)
	elseif op == "capture-stop" then
		runJson({ "stats", "record", "stop" }, function()
			refreshStats()
		end)
	elseif op == "host-start" then
		setHostEnabled(true)
	elseif op == "host-stop" then
		setHostEnabled(false)
	elseif op == "open-console" then
		openConsole()
	elseif op == "verify-watch" then
		retryAt = 0
		verifyWatcher()
	end
end

local function startWatcher()
	if type(noctalia.runStream) ~= "function" then
		retryAt = nowMs() + (ctl.WATCH_RETRY_MS or 15000)
		return
	end
	local ok = noctalia.runStream(ctl.watchCommand(), function(line)
		local kind, ev = ctl.eventKind(line, decodeJson)
		if not kind then
			return
		end
		if ctl.eventIsPairingPending and ctl.eventIsPairingPending(kind) then
			local device = model.eventDevice and model.eventDevice(ev) or nil
			if device then
				toastPending({ device })
			end
			refresh()
			return
		end
		if ctl.eventIsStreamStart and ctl.eventIsStreamStart(kind) then
			if type(noctalia.notify) == "function" then
				noctalia.notify("Punktfunk streaming", model.streamStartedBody(ev, snap))
			end
		elseif ctl.eventIsStreamStop and ctl.eventIsStreamStop(kind) then
			if type(noctalia.notify) == "function" then
				noctalia.notify("Punktfunk", model.streamStoppedBody(ev, snap))
			end
		end
		if kind == "ctl.resync" then
			refreshAll()
			return
		end
		if ctl.eventStopsHost(kind) then
			markStopped()
			clearPairingState()
			publish()
			return
		end
		if ctl.eventNeedsClients(kind) then
			refresh()
			refreshClients()
			return
		end
		if ctl.eventClearsHistory(kind) then
			snap.history = {}
		end
		refresh()
	end)
	watcherStarted = ok == true
	retryAt = nowMs() + (ctl.WATCH_RETRY_MS or 15000)
end

-- runStream never reports the child exiting, and an idle watch is silent, so
-- silence cannot be told from death. processMatches is the Omarchy retry.
verifyWatcher = function()
	local now = nowMs()
	if type(noctalia.processMatches) ~= "function" then
		if not watcherStarted and now >= retryAt then
			retryAt = now + (ctl.WATCH_RETRY_MS or 15000)
			startWatcher()
			refresh()
		end
		return
	end
	local needles = ctl.watchNeedles and ctl.watchNeedles() or { "punktfunk-host", "watch" }
	local queued = noctalia.processMatches(function(matched)
		if matched then
			watcherStarted = true
			return
		end
		if now < retryAt then
			return
		end
		retryAt = now + (ctl.WATCH_RETRY_MS or 15000)
		watcherStarted = false
		startWatcher()
		refresh()
	end, needles[1], needles[2])
	if not queued then
		if now >= retryAt then
			retryAt = now + (ctl.WATCH_RETRY_MS or 15000)
			watcherStarted = false
			startWatcher()
		end
	end
end

noctalia.state.watch("request", function(req)
	if type(req) ~= "table" or type(req.op) ~= "string" then
		return
	end
	local t = tonumber(req.t) or 0
	if t <= lastRequestT then
		return
	end
	lastRequestT = t
	handleRequest(req)
end)

publish()
startWatcher()
refreshAll()
noctalia.setUpdateInterval(2000)

function onEnable()
	retryAt = 0
	verifyWatcher()
	refreshAll()
end

function update()
	noctalia.setUpdateInterval(2000)
	verifyWatcher()
	local now = nowMs()
	if snap.hostBusy == true and now >= settleUntil then
		if model.hostSettled(snap) then
			snap.hostBusy = false
			snap.haveDesired = false
		else
			snap.hostBusy = false
		end
		refresh()
		refreshClients()
		refreshDisplays()
	end
	local panelOpen = noctalia.state.get("panelOpen") == true
	local panelTab = noctalia.state.get("panelTab") or "overview"
	if ctl.shouldPollStats(panelOpen, panelTab, snap.state) then
		if now - lastStatsAt >= (ctl.STATS_POLL_MS or 2000) then
			lastStatsAt = now
			refreshStats()
		end
	end
end

function onExit(_signal, _reason) end
