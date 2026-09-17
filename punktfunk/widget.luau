--!nonstrict
-- Bar widget: two-state cast glyph, urgent when a device is waiting.
-- Click opens the panel. Right-click stops a live session, or opens the web
-- console when nothing is streaming.

local model
local requireOk, requireResult = pcall(require, "./model.luau")
if requireOk and type(requireResult) == "table" then
	model = requireResult
else
	model = {
		needsYou = function(snap)
			return type(snap) == "table" and (tonumber(snap.pending) or 0) > 0
		end,
		widgetGlyph = function(snap)
			if type(snap) == "table" and snap.pinMismatch then
				return "alert-triangle"
			end
			return "cast"
		end,
		widgetColor = function(snap)
			if type(snap) == "table" and (snap.pinMismatch or (tonumber(snap.pending) or 0) > 0) then
				return "error"
			end
			if type(snap) == "table" and snap.state == "streaming" then
				return "primary"
			end
			return "on_surface"
		end,
		heroTitle = function()
			return "Punktfunk"
		end,
	}
end

local snap = noctalia.state.get("snap") or { state = "stopped", pending = 0 }

local function request(op)
	noctalia.state.set("request", {
		op = op,
		t = type(noctalia.nowMs) == "function" and noctalia.nowMs() or os.time(),
	})
end

local function tooltip()
	if type(snap) ~= "table" then
		return noctalia.tr("widget.stopped")
	end
	if snap.pinMismatch then
		return noctalia.tr("widget.pin_mismatch")
	end
	if model.needsYou(snap) then
		return noctalia.tr("widget.pending")
	end
	if snap.state == "streaming" then
		local client = type(snap.summary) == "table" and snap.summary.client_name or nil
		if client and client ~= "" then
			return "Punktfunk · " .. tostring(client)
		end
		return noctalia.tr("widget.streaming")
	end
	if snap.state == "idle" then
		return noctalia.tr("widget.idle")
	end
	return noctalia.tr("widget.stopped")
end

local function render()
	local showLabel = noctalia.getConfig("show_label") == true
	barWidget.setGlyph(model.widgetGlyph(snap))
	barWidget.setGlyphColor(model.widgetColor(snap), "script")
	if showLabel then
		barWidget.setText(noctalia.tr("widget.label"))
	else
		barWidget.setText("")
	end
	barWidget.setTooltip(tooltip())
end

noctalia.state.watch("snap", function(value)
	if type(value) == "table" then
		snap = value
		render()
	end
end)

function update()
	noctalia.setUpdateInterval(1500)
	render()
end

function onClick()
	noctalia.togglePanel("luxus/punktfunk:panel")
end

function onRightClick()
	if type(snap) == "table" and snap.state == "streaming" then
		request("stop-session")
	else
		request("open-console")
	end
end
