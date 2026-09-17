--!nonstrict
local snap = noctalia.state.get("snap") or { state = "stopped" }

local function render()
	local live = type(snap) == "table" and snap.state == "streaming"
	shortcut.setLabel(noctalia.tr("shortcut.label"))
	shortcut.setIcon("cast")
	shortcut.setActive(live)
end

noctalia.state.watch("snap", function(value)
	if type(value) == "table" then
		snap = value
		render()
	end
end)

render()

function onClick()
	noctalia.togglePanel("luxus/punktfunk:panel")
end
