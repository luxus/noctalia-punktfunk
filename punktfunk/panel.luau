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
		lastText = string.format("%s" .. tostring(digits or 1) .. "f %s", last, unit or "")
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
