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
