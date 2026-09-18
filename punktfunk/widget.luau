--!nonstrict
-- Bar widget: Punktfunk lens mark with state chrome around it.
--
-- The bar uses assets/punktfunk-mark.svg (lens only, no wordmark). Overlay
-- pending badge + semantic fill/border wrap it. Glyph is missing-file fallback.
-- Click opens the panel (Pair tab when something is waiting). Right-click
-- stops a live session, or opens the web console when nothing is streaming.

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
		widgetFill = function()
			return nil
		end,
		widgetBorder = function(snap)
			if type(snap) == "table" and snap.state == "streaming" then
				return "primary"
			end
			return "on_surface"
		end,
		widgetLogoPath = function()
			return nil
		end,
		MARK_PATH = "assets/punktfunk-mark.svg",
		WIDGET_MARK_SIZE = 16,
		widgetBadge = function(snap)
			if type(snap) == "table" and (tonumber(snap.pending) or 0) > 0 then
				return tostring(tonumber(snap.pending) or 0)
			end
			return nil
		end,
		widgetShowPip = function(snap)
			return type(snap) == "table" and snap.state == "streaming"
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

local function fileExists(path)
	if type(noctalia.fileExists) ~= "function" then
		return false
	end
	return noctalia.fileExists(path) == true
end

-- Lens mark only. Pin-mismatch / pending / streaming are overlays around it,
-- never a replacement glyph (glyph is only the missing-file fallback).
local function brandMark(color)
	local logo = model.widgetLogoPath and model.widgetLogoPath(fileExists) or nil
	local size = model.WIDGET_MARK_SIZE or 16
	if logo then
		return ui.image({ path = logo, width = size, height = size, fit = "contain" })
	end
	return ui.glyph({ name = model.widgetGlyph(snap), size = size, color = color })
end

local function overlayChildren(color)
	local children = { brandMark(color) }
	if type(snap) == "table" and snap.pinMismatch then
		table.insert(children, ui.glyph({ name = "alert-triangle", size = 10, color = "error" }))
	end
	if model.widgetShowPip and model.widgetShowPip(snap) then
		table.insert(children, ui.box({
			width = 6,
			height = 6,
			radius = 3,
			fill = "primary",
		}))
	end
	local badge = model.widgetBadge and model.widgetBadge(snap) or nil
	if badge then
		table.insert(children, ui.row({
			fill = "error",
			radius = 8,
			paddingH = 4,
			paddingV = 1,
			align = "center",
			minWidth = 12,
			minHeight = 12,
		}, {
			ui.label({ text = badge, fontSize = 10, fontWeight = "bold" }),
		}))
	end
	return children
end

local function render()
	local color = model.widgetColor(snap)
	local showLabel = noctalia.getConfig("show_label") == true
	local chrome = overlayChildren(color)
	if showLabel then
		table.insert(chrome, ui.label({
			text = noctalia.tr("widget.label"),
			color = color,
		}))
	end
	local isVertical = barWidget.isVertical and barWidget.isVertical()
	local container = isVertical and ui.column or ui.row
	local layout = {
		gap = 4,
		align = "center",
		fill = model.widgetFill and model.widgetFill(snap) or nil,
		border = model.widgetBorder and model.widgetBorder(snap) or color,
		borderWidth = 1,
		radius = 8,
	}
	if isVertical then
		layout.paddingV = 4
		layout.paddingH = 3
	else
		layout.paddingH = 5
		layout.paddingV = 2
	end
	if type(barWidget.render) == "function" and type(ui) == "table" then
		barWidget.render(container(layout, chrome))
		barWidget.setTooltip(tooltip())
		return
	end
	barWidget.setGlyph(model.widgetGlyph(snap))
	barWidget.setGlyphColor(color, "script")
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
	if model.needsYou(snap) then
		noctalia.state.set("panelTab", "pair")
		noctalia.state.set("focusPair", {
			t = type(noctalia.nowMs) == "function" and noctalia.nowMs() or os.time(),
			reason = "click",
		})
	end
	noctalia.togglePanel("luxus/punktfunk:panel")
end

function onRightClick()
	if type(snap) == "table" and snap.state == "streaming" then
		request("stop-session")
	else
		request("open-console")
	end
end
