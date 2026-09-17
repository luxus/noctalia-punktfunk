--!nonstrict
-- Punktfunk panel for Noctalia v5. Layout follows official-plugins/example/panel.luau:
-- column/row/scroll only. ui.box is a leaf swatch, not a flex parent.
-- Do not error() at load: a thrown panel entry is an empty surface.
-- All host calls go through the [[service]] via noctalia.state request.

local model
local requireOk, requireResult = pcall(require, "./model.luau")
if requireOk and type(requireResult) == "table" then
	model = requireResult
else
	model = nil
	if type(noctalia) == "table" and type(noctalia.log) == "function" then
		noctalia.log("Punktfunk: require(./model.luau) failed: " .. tostring(requireResult))
	end
end

if model == nil then
	model = {
		TAB_NAMES = { "Overview", "Pair", "Devices", "Display", "Stats" },
		TAB_IDS = { "overview", "pair", "devices", "display", "stats" },
		tabId = function(i)
			local ids = { "overview", "pair", "devices", "display", "stats" }
			return ids[(i or 0) + 1] or "overview"
		end,
		tabIndex = function()
			return 0
		end,
		nextTab = function(i, d)
			return ((i or 0) + (d or 0) + 5) % 5
		end,
		tabLabel = function(id)
			return id
		end,
		heroTitle = function()
			return "Punktfunk"
		end,
		heroMeta = function()
			return "Host is stopped"
		end,
		heroPhrase = function()
			return ""
		end,
		heroPhraseCount = function()
			return 1
		end,
		sessionLive = function()
			return false
		end,
		sessionFacts = function()
			return {}
		end,
		sessionActions = function()
			return {}
		end,
		showArmRow = function()
			return false
		end,
		incomingPair = function()
			return nil
		end,
		remainingPair = function()
			return {}
		end,
		tail = function()
			return "—"
		end,
		allPresets = function(a, b)
			local out = {}
			for _, x in ipairs(a or {}) do
				table.insert(out, x)
			end
			for _, x in ipairs(b or {}) do
				table.insert(out, x)
			end
			return out
		end,
		policyRows = function()
			return {}
		end,
		statsPillars = function()
			return {}
		end,
		sparkPoints = function()
			return {}
		end,
		chartSeries = function()
			return {}
		end,
		graphValues = function()
			return {}
		end,
		seriesLast = function()
			return nil
		end,
		concatDevices = function(a, b)
			local out = {}
			for _, x in ipairs(a or {}) do
				table.insert(out, x)
			end
			for _, x in ipairs(b or {}) do
				table.insert(out, x)
			end
			return out
		end,
		devicePlane = function()
			return "moonlight"
		end,
		deviceTitle = function()
			return "(unnamed device)"
		end,
		needsYou = function()
			return false
		end,
		hostEnabled = function(s)
			return type(s) == "table" and s.state ~= "stopped"
		end,
		pinArgs = function()
			return {}
		end,
	}
end

local open = false
local currentTab = 0
local phraseIndex = 0
local lastPhraseAt = 0
local unpairFingerprint = ""
local pinDraft = ""
local snap = noctalia.state.get("snap") or {
	state = "stopped",
	pending = 0,
	games = {},
	summary = {},
	history = {},
	nativeClients = {},
	gamestreamClients = {},
	pinDevices = {},
	pendingDevices = {},
	displayEffective = {},
	displayPresets = {},
	customPresets = {},
}

local function nowMs()
	if type(noctalia.nowMs) == "function" then
		return noctalia.nowMs()
	end
	return os.time() * 1000
end

local function request(op, extra)
	local req = extra or {}
	req.op = op
	req.t = nowMs()
	noctalia.state.set("request", req)
end

local function tabId()
	return model.tabId(currentTab)
end

local function setTab(index)
	currentTab = index
	unpairFingerprint = ""
	noctalia.state.set("panelTab", tabId())
	if tabId() == "display" then
		request("refresh-displays")
	end
	if tabId() == "devices" or tabId() == "pair" then
		request("refresh-clients")
	end
	if (tabId() == "stats" or tabId() == "overview") and snap.state == "streaming" then
		request("refresh-stats")
	end
end

local function paint()
	if not open then
		return
	end
	if type(panel) ~= "table" or type(panel.render) ~= "function" then
		return
	end
	if type(ui) ~= "table" then
		return
	end
	panel.render(tree())
end

local function factGrid(facts)
	local rows = {}
	local i = 1
	while i <= #facts do
		local cells = {
			ui.column({ flexGrow = 1, gap = 2, key = "fact-a-" .. tostring(i) }, {
				ui.label({ text = facts[i].k, fontSize = 12, color = "on_surface_variant" }),
				ui.label({ text = facts[i].v, fontWeight = "medium" }),
			}),
		}
		if facts[i + 1] then
			table.insert(cells, ui.column({ flexGrow = 1, gap = 2, key = "fact-b-" .. tostring(i) }, {
				ui.label({ text = facts[i + 1].k, fontSize = 12, color = "on_surface_variant" }),
				ui.label({ text = facts[i + 1].v, fontWeight = "medium" }),
			}))
		end
		table.insert(rows, ui.row({ gap = 12, key = "facts-" .. tostring(i) }, cells))
		i = i + 2
	end
	return rows
end

local function pillarsRow(pillars)
	if #pillars == 0 then
		return nil
	end
	local cells = {}
	for i, pillar in ipairs(pillars) do
		table.insert(cells, ui.column({ flexGrow = 1, gap = 6, key = "pillar-" .. pillar.label }, {
			ui.label({ text = pillar.label, fontSize = 11, color = "on_surface_variant" }),
			ui.label({ text = pillar.text, fontSize = 22, fontWeight = "bold" }),
			ui.progress({ progress = pillar.meter or 0, height = 4, radius = 2 }),
			ui.label({ text = pillar.note, fontSize = 11, color = "on_surface_variant" }),
		}))
	end
	return ui.row({ gap = 14, key = "pillars" }, cells)
end

local function sparkBlock(label, unit, digits, pts)
	local last = model.seriesLast(pts)
	local lastText = "—"
	if last ~= nil then
		lastText = string.format("%." .. tostring(digits or 1) .. "f %s", last, unit or "")
	end
	local values = model.graphValues(pts)
	local children = {
		ui.row({ align = "center", key = "spark-h-" .. label }, {
			ui.label({ text = label, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
			ui.label({ text = lastText, fontSize = 12 }),
		}),
	}
	if #values >= 2 then
		table.insert(children, ui.graph({
			values = values,
			width = 480,
			height = 36,
			color = "primary",
			lineWidth = 1.5,
			fillOpacity = 0.16,
		}))
	else
		table.insert(children, ui.label({ text = "collecting…", fontSize = 12, color = "on_surface_variant" }))
	end
	return ui.column({ gap = 4, key = "spark-" .. label }, children)
end

local function overviewTab()
	local live = model.sessionLive(snap.state, snap.sessions, snap.games)
	local facts = model.sessionFacts(snap)
	local actions = model.sessionActions(live, type(snap.games) == "table" and #snap.games > 0)
	local pillars = model.statsPillars(snap)
	local children = factGrid(facts)
	if live and type(snap.games) == "table" and #snap.games == 0 then
		table.insert(children, ui.label({
			text = "No game was launched through Punktfunk — this is the desktop.",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	for i, game in ipairs(snap.games or {}) do
		local extra = ""
		if game.state == "grace" then
			extra = " · reconnecting"
		end
		table.insert(children, ui.column({ gap = 2, key = "game-" .. tostring(i) }, {
			ui.label({ text = game.title or "Desktop", fontWeight = "medium" }),
			ui.label({
				text = tostring(game.client or "—") .. " · " .. tostring(game.plane or "") .. extra,
				fontSize = 12,
				color = "on_surface_variant",
			}),
		}))
	end
	for _, action in ipairs(actions) do
		local op = action.id == "end" and "end-game" or "stop-session"
		table.insert(children, ui.button({
			key = "action-" .. action.id,
			text = action.label,
			variant = "destructive",
			onClick = function()
				request(op)
			end,
		}))
	end
	local pillarsNode = pillarsRow(pillars)
	if pillarsNode then
		table.insert(children, pillarsNode)
	end
	if live then
		table.insert(children, sparkBlock("Target", "Mbps", 1, model.sparkPoints(snap.history, "target")))
	end
	return ui.column({ gap = 12, key = "overview" }, children)
end

local function pairTab()
	local incoming = model.incomingPair(snap.pendingDevices)
	local extra = model.remainingPair(snap.pendingDevices)
	local showArm = model.showArmRow(snap.state)
	local children = {}
	if incoming then
		table.insert(children, ui.column({
			key = "incoming",
			gap = 8,
			padding = 10,
			fill = "primary/0.14",
			border = "primary",
			borderWidth = 1,
			radius = 8,
		}, {
			ui.label({
				text = "Pairing request from " .. model.deviceTitle(incoming),
				fontWeight = "bold",
			}),
			ui.label({
				text = model.tail(incoming.fingerprint) .. " · " .. tostring(incoming.age_secs or 0) .. "s ago",
				fontSize = 12,
				color = "on_surface_variant",
			}),
			ui.row({ gap = 8 }, {
				ui.button({
					text = "Accept",
					variant = "primary",
					onClick = function()
						request("approve", { id = incoming.id })
					end,
				}),
				ui.button({
					text = "Reject",
					variant = "destructive",
					onClick = function()
						request("deny", { id = incoming.id })
					end,
				}),
			}),
		}))
	end
	if showArm and snap.armed and type(snap.pairingPin) == "string" and snap.pairingPin ~= "" then
		table.insert(children, ui.column({ key = "verify-pin", gap = 4, padding = 10, fill = "surface_variant/0.5", radius = 8 }, {
			ui.label({ text = "Verify on both devices", fontSize = 12, color = "on_surface_variant" }),
			ui.label({ text = snap.pairingPin, fontSize = 24, fontWeight = "bold" }),
		}))
	end
	if showArm then
		local hint = "Open a pairing window, then add this host on the device."
		if snap.armed then
			if snap.pairingPin and snap.pairingPin ~= "" then
				hint = "Enter " .. snap.pairingPin .. " on the device"
			else
				hint = "Add this host on the device"
			end
		end
		table.insert(children, ui.row({ key = "arm", gap = 12, align = "center" }, {
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({ text = snap.armed and "Pairing window open" or "Pairing window", fontWeight = "medium" }),
				ui.label({ text = hint, fontSize = 12, color = "on_surface_variant" }),
			}),
			ui.toggle({
				checked = snap.armed == true,
				onChange = function(value)
					if value == "true" then
						request("pair-arm")
					else
						request("pair-disarm")
					end
				end,
			}),
		}))
	end
	if type(snap.pinDevices) == "table" and #snap.pinDevices > 0 then
		table.insert(children, ui.label({ text = "Moonlight is waiting for a PIN", fontWeight = "medium" }))
		for i, device in ipairs(snap.pinDevices) do
			table.insert(children, ui.column({ key = "pin-" .. tostring(i), gap = 8 }, {
				ui.input({
					key = "pin-field-" .. tostring(device.uniqueid or i),
					placeholder = device.uniqueid and ("PIN · " .. tostring(device.uniqueid)) or "Moonlight PIN",
					onChange = function(value)
						pinDraft = value
					end,
					onSubmit = function(value)
						request("pin", {
							pin = value,
							uniqueid = device.uniqueid,
							fingerprint = device.fingerprint,
							peer_ip = device.peer_ip,
						}),
					end,
				}),
				ui.button({
					text = "Submit",
					variant = "primary",
					onClick = function()
						request("pin", {
							pin = pinDraft,
							uniqueid = device.uniqueid,
							fingerprint = device.fingerprint,
							peer_ip = device.peer_ip,
						})
					end,
				}),
			}))
		end
	end
	for i, device in ipairs(extra) do
		table.insert(children, ui.row({ key = "pending-" .. tostring(i), gap = 8, align = "center" }, {
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({ text = model.deviceTitle(device) }),
				ui.label({
					text = model.tail(device.fingerprint) .. " · " .. tostring(device.age_secs or 0) .. "s ago",
					fontSize = 12,
					color = "on_surface_variant",
				}),
			}),
			ui.button({
				text = "Accept",
				variant = "primary",
				controlSize = "sm",
				onClick = function()
					request("approve", { id = device.id })
				end,
			}),
			ui.button({
				text = "Reject",
				variant = "ghost",
				controlSize = "sm",
				onClick = function()
					request("deny", { id = device.id })
				end,
			}),
		}))
	end
	if not showArm and not incoming and #(snap.pinDevices or {}) == 0 then
		table.insert(children, ui.label({
			text = "Start the host to open a pairing window.",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	return ui.column({ gap = 12, key = "pair" }, children)
end

local function devicesTab()
	local devices = model.concatDevices(snap.nativeClients, snap.gamestreamClients)
	local children = {}
	if #devices == 0 then
		table.insert(children, ui.label({
			text = "No devices are paired yet. Open a pairing window, then add this host on the device.",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	else
		table.insert(children, ui.label({
			text = "DEVICES · " .. tostring(#devices),
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	for i, device in ipairs(devices) do
		local fingerprint = device.fingerprint or ""
		local confirming = fingerprint ~= "" and unpairFingerprint == fingerprint
		local buttons
		if confirming then
			buttons = ui.row({ gap = 6 }, {
				ui.button({
					text = "Confirm",
					variant = "destructive",
					controlSize = "sm",
					onClick = function()
						request("unpair", { fingerprint = fingerprint })
						unpairFingerprint = ""
						paint()
					end,
				}),
				ui.button({
					text = "Cancel",
					variant = "ghost",
					controlSize = "sm",
					onClick = function()
						unpairFingerprint = ""
						paint()
					end,
				}),
			})
		else
			buttons = ui.button({
				text = "Unpair",
				variant = "ghost",
				controlSize = "sm",
				onClick = function()
					unpairFingerprint = fingerprint
					paint()
				end,
			})
		end
		local access = ""
		if device.access_level then
			access = " · " .. tostring(device.access_level)
		end
		table.insert(children, ui.row({ key = "device-" .. fingerprint .. "-" .. tostring(i), gap = 8, align = "center" }, {
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({ text = model.deviceTitle(device), fontWeight = "medium" }),
				ui.label({
					text = model.tail(fingerprint) .. " · " .. model.devicePlane(device) .. access,
					fontSize = 12,
					color = "on_surface_variant",
				}),
			}),
			buttons,
		}))
	end
	return ui.column({ gap = 10, key = "devices" }, children)
end

local function modeCard(kind, label, detail)
	local current = snap.captureMode == kind
	return ui.column({
		key = "mode-" .. kind,
		flexGrow = 1,
		gap = 4,
		padding = 12,
		align = "center",
		fill = current and "primary/0.18" or "surface_variant/0.45",
		border = current and "primary" or "outline",
		borderWidth = 1,
		radius = 8,
		onClick = function()
			request("capture-mode", { mode = kind })
		end,
	}, {
		ui.label({ text = label, fontWeight = "bold", textAlign = "center" }),
		ui.label({ text = detail, fontSize = 12, color = "on_surface_variant", textAlign = "center" }),
	})
end

local function devicesDisplayTab()
	local presets = model.allPresets(snap.displayPresets, snap.customPresets)
	local policy = model.policyRows(snap.displayEffective)
	local title = snap.captureMode == "mirror" and "This screen" or "Dedicated display"
	local children = {
		ui.column({ gap = 2, key = "display-hero" }, {
			ui.label({ text = title, fontSize = 20, fontWeight = "bold" }),
			ui.label({ text = snap.displayPreset ~= "" and snap.displayPreset or "no preset", fontSize = 12, color = "on_surface_variant" }),
		}),
		ui.row({ gap = 10, key = "mode-cards" }, {
			modeCard("dedicated", "Dedicated", "Virtual display at the client's size"),
			modeCard("mirror", "This screen", "The primary monitor on this box"),
		}),
	}
	for _, row in ipairs(factGrid(policy)) do
		table.insert(children, row)
	end
	if #presets > 0 then
		table.insert(children, ui.label({ text = "PRESETS", fontSize = 12, color = "on_surface_variant" }))
	end
	for i, preset in ipairs(presets) do
		local current = snap.displayPreset == preset.id
		table.insert(children, ui.row({
			key = "preset-" .. tostring(preset.id or i),
			gap = 8,
			align = "center",
			padding = 6,
			fill = current and "primary/0.14" or nil,
			radius = 6,
			onClick = function()
				request("display-preset", { id = preset.id })
			end,
		}, {
			ui.glyph({ name = current and "check" or "point", size = 16 }),
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({ text = preset.name or preset.id or "", fontWeight = current and "bold" or "medium" }),
				ui.label({
					text = preset.summary or (preset.fields and "Saved preset." or ""),
					fontSize = 12,
					color = "on_surface_variant",
					visible = (preset.summary or preset.fields) ~= nil,
				}),
			}),
		}))
	end
	if #presets > 0 then
		table.insert(children, ui.label({
			text = "Named virtual heads can survive a disconnect on compositors that keep them. Hosts without that support still tear the head down with the session.",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	return ui.column({ gap = 12, key = "display" }, children)
end

local function statsTab()
	local children = {}
	if not snap.stream then
		local text = "Nothing is streaming, so there is nothing to measure."
		if snap.state == "stopped" then
			text = "The host is not running."
		end
		table.insert(children, ui.label({ text = text, fontSize = 12, color = "on_surface_variant" }))
		return ui.column({ gap = 12, key = "stats" }, children)
	end
	table.insert(children, ui.label({
		text = tostring(snap.stream.width) .. "×" .. tostring(snap.stream.height) .. " @ " .. tostring(snap.stream.fps) .. " · " .. string.upper(tostring(snap.stream.codec or "")),
	}))
	local pillars = pillarsRow(model.statsPillars(snap))
	if pillars then
		table.insert(children, pillars)
	end
	if tonumber(snap.stream.time_to_first_frame_ms) and tonumber(snap.stream.time_to_first_frame_ms) > 0 then
		table.insert(children, ui.label({
			text = tostring(snap.stream.time_to_first_frame_ms) .. " ms to the first frame",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	if type(snap.statsMeta) == "table" and snap.statsMeta.encoder_backend then
		local gpu = snap.statsMeta.gpu and (" · " .. tostring(snap.statsMeta.gpu)) or ""
		table.insert(children, ui.label({
			text = tostring(snap.statsMeta.encoder_backend) .. gpu,
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	table.insert(children, ui.separator({}))
	local captureLabel = "FRAME TIMINGS"
	if snap.captureArmed then
		captureLabel = "FRAME TIMINGS · " .. tostring(snap.captureSamples) .. " samples"
	end
	table.insert(children, ui.row({ align = "center", gap = 8 }, {
		ui.label({ text = captureLabel, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
		ui.button({
			text = snap.captureArmed and "Stop capture" or "Record timings",
			variant = snap.captureArmed and "destructive" or "secondary",
			controlSize = "sm",
			onClick = function()
				if snap.captureArmed then
					request("capture-stop")
				else
					request("capture-start")
				end
			end,
		}),
	}))
	if not snap.captureArmed then
		table.insert(children, ui.label({
			text = "Per-frame drops and stage timings are only sampled while a capture is recording. Stopping saves it; the web console graphs the saved ones.",
			fontSize = 12,
			color = "on_surface_variant",
		}))
	end
	for _, series in ipairs(model.chartSeries(snap.captureArmed)) do
		table.insert(children, sparkBlock(series.label, series.unit, series.digits, model.sparkPoints(snap.history, series.key)))
	end
	return ui.column({ gap = 12, key = "stats" }, children)
end

function tree()
	local tabs = {}
	for i, name in ipairs(model.TAB_NAMES) do
		local id = model.tabId(i - 1)
		local selected = currentTab == (i - 1)
		table.insert(tabs, ui.button({
			key = "tab-" .. id,
			text = model.tabLabel(id, snap.pending),
			variant = selected and "primary" or "ghost",
			controlSize = "sm",
			flexGrow = 1,
			onClick = function()
				setTab(i - 1)
				paint()
			end,
		}))
	end
	local body
	local id = tabId()
	if id == "pair" then
		body = pairTab()
	elseif id == "devices" then
		body = devicesTab()
	elseif id == "display" then
		body = devicesDisplayTab()
	elseif id == "stats" then
		body = statsTab()
	else
		body = overviewTab()
	end
	local headerChildren = {
		ui.column({ flexGrow = 1, gap = 2 }, {
			ui.label({
				text = model.heroTitle(snap.state, type(snap.summary) == "table" and snap.summary.client_name or nil),
				fontSize = 16,
				fontWeight = "bold",
				color = "on_surface",
			}),
			ui.label({
				text = model.heroMeta(snap.state, model.heroPhrase(phraseIndex)),
				fontSize = 12,
				color = "on_surface_variant",
			}),
		}),
		ui.toggle({
			checked = model.hostEnabled(snap) == true,
			onChange = function(value)
				if value == "true" then
					request("host-start")
				else
					request("host-stop")
				end
			end,
		}),
		ui.button({ glyph = "close", onClick = "onCloseClicked" }),
	}
	local stack = {
		ui.row({ align = "center", justify = "space_between", gap = 8, key = "header" }, headerChildren),
	}
	if snap.pinMismatch then
		table.insert(stack, ui.label({
			text = "The process answering the management port did not present this host's certificate, so no credential was sent. Either the host regenerated its identity, or something else is on that port.",
			color = "error",
			fontSize = 12,
		}))
	end
	if snap.lastError and snap.lastError ~= "" and not snap.pinMismatch then
		table.insert(stack, ui.label({ text = snap.lastError, color = "error", fontSize = 12 }))
	end
	table.insert(stack, ui.row({ gap = 6, key = "tabs" }, tabs))
	table.insert(stack, ui.scroll({ flexGrow = 1, gap = 12, key = "body" }, { body }))
	return ui.column({ flexGrow = 1, gap = 16 }, stack)
end

noctalia.state.watch("snap", function(value)
	if type(value) == "table" then
		snap = value
		if open and model.needsYou(snap) and tabId() ~= "pair" then
			-- A waiting pair opens the Pair tab, matching the Omarchy plugin.
			currentTab = model.tabIndex("pair")
			noctalia.state.set("panelTab", "pair")
		end
		paint()
	end
end)

function onOpen(_context)
	open = true
	unpairFingerprint = ""
	pinDraft = ""
	if model.needsYou(snap) then
		currentTab = model.tabIndex("pair")
	end
	noctalia.state.set("panelOpen", true)
	noctalia.state.set("panelTab", tabId())
	request("refresh-all")
	paint()
end

function onClose()
	open = false
	noctalia.state.set("panelOpen", false)
end

function update()
	noctalia.setUpdateInterval(2000)
	if not open then
		return
	end
	if snap.state == "streaming" then
		local t = nowMs()
		if t - lastPhraseAt >= 2800 then
			lastPhraseAt = t
			phraseIndex = (phraseIndex + 1) % math.max(1, model.heroPhraseCount())
			paint()
		end
	end
end

function onKey(chord, pressed)
	if not pressed then
		return
	end
	if chord == "1" or chord == "2" or chord == "3" or chord == "4" or chord == "5" then
		setTab(tonumber(chord) - 1)
		paint()
		return
	end
	if chord == "h" then
		setTab(model.nextTab(currentTab, -1))
		paint()
		return
	end
	if chord == "l" then
		setTab(model.nextTab(currentTab, 1))
		paint()
		return
	end
	if chord == "x" then
		local incoming = model.incomingPair(snap.pendingDevices)
		if incoming then
			request("deny", { id = incoming.id })
		end
		return
	end
	if chord == "y" and unpairFingerprint ~= "" then
		request("unpair", { fingerprint = unpairFingerprint })
		unpairFingerprint = ""
		paint()
		return
	end
	if chord == "c" and unpairFingerprint ~= "" then
		unpairFingerprint = ""
		paint()
	end
end

function onCloseClicked()
	panel.close()
end
