--!nonstrict
-- argv builders and host-envelope helpers for punktfunk-host ctl.
-- Pure module: no noctalia globals, never HTTPS, never the operator token.
-- plugin_api 24 `require("./ctl.luau")` — callers spawn via noctalia.runAsync(argv).

local ctl = {}

ctl.EXIT_PIN = 4
ctl.HISTORY_MAX = 90
ctl.WATCH_RETRY_MS = 15000
ctl.STATS_POLL_MS = 2000
ctl.HOST_SETTLE_MS = 1500
ctl.WATCH_KINDS = "pairing.*,stream.*,session.*,host.*"
ctl.ACCESS_LEVELS = { "full", "controller", "view" }

function ctl.hostBin()
	return "punktfunk-host"
end

function ctl.hostArgv(args)
	local argv = { ctl.hostBin(), "ctl" }
	for _, arg in ipairs(args or {}) do
		table.insert(argv, arg)
	end
	return argv
end

function ctl.jsonArgv(args)
	local argv = ctl.hostArgv(args)
	table.insert(argv, "--json")
	return argv
end

function ctl.watchArgv()
	return ctl.hostArgv({ "watch", "--kinds", ctl.WATCH_KINDS })
end

-- runStream is a shell string (plugin_api 24 argv form is runAsync only).
-- Quote kinds so pairing.* cannot glob-expand in the plugin cwd.
function ctl.watchCommand()
	return "punktfunk-host ctl watch --kinds '" .. ctl.WATCH_KINDS .. "'"
end

function ctl.watchNeedles()
	return { "punktfunk-host", "watch" }
end

function ctl.isAccessLevel(level)
	local wanted = tostring(level or "")
	for _, name in ipairs(ctl.ACCESS_LEVELS) do
		if name == wanted then
			return true
		end
	end
	return false
end

function ctl.accessArgv(fingerprint, level)
	return ctl.jsonArgv({ "access", tostring(fingerprint or ""), tostring(level or "") })
end

function ctl.renameArgv(fingerprint, name)
	return ctl.jsonArgv({ "rename", tostring(fingerprint or ""), tostring(name or "") })
end

function ctl.displayReleaseArgv(slot)
	if slot ~= nil and tostring(slot) ~= "" then
		return ctl.jsonArgv({ "display", "release", tostring(slot) })
	end
	return ctl.jsonArgv({ "display", "release" })
end

function ctl.listMonitorsArgv()
	return { ctl.hostBin(), "list-monitors" }
end

function ctl.systemctlArgv(action, unit)
	return { "systemctl", "--user", action, unit or "punktfunk-host.service" }
end

function ctl.missingCtlMessage()
	return "punktfunk-host ctl did not answer (is the host installed?)"
end

-- decoded is the JSON object from stdout, or nil when parse failed.
function ctl.interpret(decoded, exitCode, raw)
	if type(decoded) ~= "table" then
		return nil, { code = exitCode, message = ctl.missingCtlMessage() }
	end
	if type(decoded.error) == "table" then
		local err = decoded.error
		return nil, {
			code = err.code,
			message = err.message or ctl.missingCtlMessage(),
		}
	end
	if exitCode == 0 then
		return decoded.data, nil
	end
	local message = raw
	if message == nil or message == "" then
		message = "command exited with code " .. tostring(exitCode)
	end
	return nil, { code = exitCode, message = tostring(message) }
end

function ctl.isPinMismatch(err)
	return type(err) == "table" and tonumber(err.code) == ctl.EXIT_PIN
end

function ctl.displaySettingsPath(configHome)
	local home = configHome
	if type(home) ~= "string" or home == "" then
		home = "~/.config"
	end
	return home .. "/punktfunk/display-settings.json"
end

function ctl.hostEnvPath(configHome)
	local home = configHome
	if type(home) ~= "string" or home == "" then
		home = "~/.config"
	end
	return home .. "/punktfunk/host.env"
end

function ctl.hostEnvHasCapturePin(text)
	if type(text) ~= "string" then
		return false
	end
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		local trimmed = string.gsub(line, "^%s+", "")
		if string.sub(trimmed, 1, #"PUNKTFUNK_CAPTURE_MONITOR=") == "PUNKTFUNK_CAPTURE_MONITOR=" then
			local value = string.sub(trimmed, #"PUNKTFUNK_CAPTURE_MONITOR=" + 1)
			value = string.gsub(value, "^%s+", "")
			value = string.gsub(value, "%s+$", "")
			value = string.gsub(value, "^['\"]", "")
			value = string.gsub(value, "['\"]$", "")
			if value ~= "" then
				return true
			end
		end
	end
	return false
end

function ctl.stripCapturePin(text)
	if type(text) ~= "string" then
		return ""
	end
	local kept = {}
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		local trimmed = string.gsub(line, "^%s+", "")
		if string.sub(trimmed, 1, #"PUNKTFUNK_CAPTURE_MONITOR=") ~= "PUNKTFUNK_CAPTURE_MONITOR=" then
			table.insert(kept, line)
		end
	end
	if #kept == 0 then
		return ""
	end
	return table.concat(kept, "\n") .. "\n"
end

-- Host policy gates in host.env (take effect next session). Default on.
-- 0 / false / off / no forces SDR or 4:2:0; the client still picks per session.
ctl.ENV_10BIT = "PUNKTFUNK_10BIT"
ctl.ENV_444 = "PUNKTFUNK_444"

local function envAssignment(line, key)
	if type(line) ~= "string" or type(key) ~= "string" or key == "" then
		return nil, false
	end
	local trimmed = string.gsub(line, "^%s+", "")
	if string.sub(trimmed, 1, 1) == "#" then
		return nil, false
	end
	local prefix = key .. "="
	if string.sub(trimmed, 1, #prefix) ~= prefix then
		return nil, false
	end
	local value = string.sub(trimmed, #prefix + 1)
	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "")
	value = string.gsub(value, "^['\"]", "")
	value = string.gsub(value, "['\"]$", "")
	return value, true
end

function ctl.hostEnvValue(text, key)
	if type(text) ~= "string" then
		return nil
	end
	local found = nil
	local any = false
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		local value, matched = envAssignment(line, key)
		if matched then
			found = value
			any = true
		end
	end
	if not any then
		return nil
	end
	return found
end

function ctl.hostEnvBool(text, key, defaultOn)
	local value = ctl.hostEnvValue(text, key)
	if value == nil or value == "" then
		return defaultOn ~= false
	end
	local lower = string.lower(value)
	if lower == "0" or lower == "false" or lower == "off" or lower == "no" then
		return false
	end
	return true
end

function ctl.hostEnvSet(text, key, value)
	local wanted = tostring(key) .. "=" .. tostring(value)
	local src = type(text) == "string" and text or ""
	local kept = {}
	local found = false
	for line in string.gmatch(src .. "\n", "(.-)\n") do
		local _, matched = envAssignment(line, key)
		if matched then
			if not found then
				table.insert(kept, wanted)
				found = true
			end
		else
			table.insert(kept, line)
		end
	end
	if not found then
		while #kept > 0 and kept[#kept] == "" do
			table.remove(kept)
		end
		table.insert(kept, wanted)
	end
	if #kept == 0 then
		return wanted .. "\n"
	end
	return table.concat(kept, "\n") .. "\n"
end

function ctl.captureModeFromConfig(displaySettings, hostEnvText)
	if ctl.hostEnvHasCapturePin(hostEnvText) then
		return "mirror"
	end
	if type(displaySettings) == "table" then
		local cm = displaySettings.capture_monitor
		if type(cm) == "string" then
			local trimmed = string.gsub(cm, "^%s+", "")
			trimmed = string.gsub(trimmed, "%s+$", "")
			if trimmed ~= "" then
				return "mirror"
			end
		end
	end
	return "dedicated"
end

function ctl.applyCaptureMonitor(displaySettings, connector)
	local data = {}
	if type(displaySettings) == "table" then
		for key, value in pairs(displaySettings) do
			data[key] = value
		end
	end
	if connector == nil or connector == "" then
		data.capture_monitor = nil
	else
		data.capture_monitor = connector
	end
	return data
end

-- Port of the Omarchy helper's primary_connector: first physical head tagged
-- primary, else the sole remaining physical head. Virtual/disabled skipped.
function ctl.primaryConnector(listOutput)
	if type(listOutput) ~= "string" then
		return nil
	end
	local physical = {}
	local primary = nil
	for line in string.gmatch(listOutput .. "\n", "(.-)\n") do
		if string.sub(line, 1, 1) == " " or string.sub(line, 1, 1) == "\t" then
			local s = string.gsub(line, "^%s+", "")
			s = string.gsub(s, "%s+$", "")
			if s ~= "" then
				local conn = string.match(s, "^(%S+)")
				if conn and string.sub(conn, -1) ~= ":" then
					local tags = string.match(s, "%[(.*)%]$") or ""
					local isVirtual = false
					local isDisabled = false
					local isPrimary = false
					for part in string.gmatch(tags .. ",", "([^,]*),") do
						local tag = string.gsub(part, "^%s+", "")
						tag = string.gsub(tag, "%s+$", "")
						if tag == "punktfunk virtual display" then
							isVirtual = true
						elseif tag == "disabled" then
							isDisabled = true
						elseif tag == "primary" then
							isPrimary = true
						end
					end
					if not isVirtual and not isDisabled then
						table.insert(physical, conn)
						if isPrimary then
							primary = conn
						end
					end
				end
			end
		end
	end
	if primary then
		return primary
	end
	if #physical == 1 then
		return physical[1]
	end
	return nil
end

function ctl.consoleFallbackUrl()
	return "https://localhost:47992"
end

function ctl.consoleUrlFromOutput(stdout, exitCode)
	if exitCode == 0 and type(stdout) == "string" then
		local url = string.match(stdout, "%S+")
		if url and string.sub(url, 1, 4) == "http" then
			return url
		end
	end
	return ctl.consoleFallbackUrl()
end

function ctl.xdgOpenArgv(url)
	return { "xdg-open", url }
end

function ctl.shouldPollStats(panelOpen, tab, state)
	return panelOpen == true and state == "streaming" and (tab == "overview" or tab == "stats")
end

function ctl.eventKind(line, decode)
	if type(line) ~= "string" or line == "" then
		return nil
	end
	if type(decode) ~= "function" then
		return nil
	end
	local ev = decode(line)
	if type(ev) == "table" and type(ev.kind) == "string" then
		return ev.kind, ev
	end
	return nil
end

function ctl.eventClearsHistory(kind)
	return kind == "stream.stopped" or kind == "session.ended"
end

function ctl.eventStopsHost(kind)
	return kind == "ctl.disconnected" or kind == "host.stopping"
end

function ctl.eventNeedsClients(kind)
	return kind == "pairing.completed" or kind == "pairing.denied" or kind == "host.started"
end

function ctl.eventIsPairingPending(kind)
	return kind == "pairing.pending"
end

function ctl.eventIsStreamStart(kind)
	return kind == "stream.started"
end

function ctl.eventIsStreamStop(kind)
	return kind == "stream.stopped"
end

return ctl
