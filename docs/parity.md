# Omarchy vs Noctalia plugin parity

Feature-parity audit of the shipped Noctalia plugin (`luxus/punktfunk` in this repo) against the Omarchy/Quickshell plugin, plus unused `punktfunk-host ctl` / watch surface.

Investigation only. No plugin behaviour was changed in this pass.

## Sources (verified against files)

| Tree | Ref | What was read |
| --- | --- | --- |
| Omarchy plugin + helpers | [`luxus/punktfunk`](https://github.com/luxus/punktfunk) `@3897a989d7d64e676aed13ae762a8a9806eb8743` | `packaging/linux/omarchy/plugin/{Panel.qml,Service.qml,Model.js,README.md,manifest.json}`, `packaging/linux/omarchy/hooks/*`, `packaging/linux/omarchy/punktfunk-omarchy` |
| Noctalia plugin | this repo (`luxus/noctalia-punktfunk`) | `punktfunk/{panel,service,model,widget,shortcut,ctl}.luau`, `plugin.toml`, `README.md` |
| Host CLI / events | same punktfunk checkout | `crates/punktfunk-host/src/ctl.rs`, `ctl/watch.rs`, `events.rs` (`EventKind`), `docs-site/content/docs/host-cli.md`, `docs-site/content/docs/automation.md` |

Trust boundary (both plugins, host docs): the plugin must keep using `punktfunk-host ctl` only. It must not speak HTTPS, hold the operator token, or see the host certificate. HTTP paths below are the routes `ctl` itself calls; they are **not** a plugin API.

Status key: **full** = same user-visible capability; **partial** = same intent, missing a control or cue; **missing** = Omarchy (plugin or its shipped hooks/helper) has it, Noctalia does not; **noctalia-only** = Noctalia has it, Omarchy plugin does not.

---

## A. Parity matrix

Rows are user-visible capabilities from the Omarchy bar plugin and the hooks `punktfunk-omarchy setup` installs next to it. Notes cite symbols and paths.

| Capability | Omarchy | Noctalia | Status | Notes |
| --- | --- | --- | --- | --- |
| Bar: stopped / idle / streaming | Two-ring `LensMark`; filled while streaming, dim when stopped (`Panel.qml` `glyphColor`, `filled: service.state === "streaming"`) | `cast` / `cast-off` glyph; streaming = `primary`, idle = `on_surface`, stopped = `on_surface_variant` (`model.widgetGlyph` / `widgetColor`) | partial | Same three states. Noctalia has no filled-vs-outline mark. |
| Bar: device waiting | Urgent colour **and** corner badge (`needsYou` `Rectangle` on the mark) | Error colour on the same glyph; tooltip `widget.pending` | partial | No overlay badge. `needsYou` = `pending > 0` or `pinPending`. |
| Bar: certificate pin mismatch (ctl exit 4) | Warning glyph `󰀦`, urgent colour, distinct tooltip/panel copy (`Service.qml` `pinMismatch`, `exitPin: 4`) | `alert-triangle`, `error` colour, `widget.pin_mismatch` (`ctl.isPinMismatch`, `EXIT_PIN`) | full | Same distinction from “host down”. |
| Click opens panel | `BarIconButton` left-click → `root.toggle()` | `widget.onClick` → `noctalia.togglePanel("luxus/punktfunk:panel")` | full | |
| Right-click: stop session or open console | Streaming → `ctl stop-session`; else `openConsole()` (`Panel.qml` `onPressed`) | Same split (`widget.onRightClick`) | full | Console launcher differs (see Console row). |
| Bar tooltip / label | Implicit via mark + panel; no text label setting | Tooltips in `translations/en.json`; optional `show_label` setting | noctalia-only | Omarchy `manifest.json` is bar-widget only. |
| Control-center / shortcut tile | Omarchy IPC (`manageIpc: true`, `ipcTarget: "punktfunk"`) — bar plugin, no separate shortcut file | `shortcut.luau` tile; active while streaming; click opens the same panel | noctalia-only | Different host chrome, same “open panel” job. |
| Panel: five tabs | Overview / Pair / Devices / Display / Stats (`Model.TAB_IDS`) | Same ids and names (`model.TAB_IDS`) | full | |
| Tab badge: Pair · N | `tabLabel(id, pending)` | Same (`model.tabLabel`) | full | |
| Waiting pair focuses Pair tab | `onOpened` + snap path (`needsYou` → `tabIndex("pair")`) | Same in `panel.onOpen` and `state.watch("snap")` | full | |
| Hero: title / rotating phrases / host toggle | `heroTitle` / `heroMeta` / `ACTIVE_PHRASES`; `ToggleSwitch` → `setHostEnabled`; 2800 ms phrase timer with fade | Same phrases and toggle (`request("host-start"|"host-stop")`); phrase swap without fade | partial | Copy and toggle are full; animation is Omarchy-only. |
| Hero: live codec | `PanelHero.detail` = `stream.codec` | Not shown in header (codec is on Stats) | partial | Overview facts also omit codec. |
| Host start / stop | `systemctl --user start\|stop punktfunk-host.service` (`Service.setHostEnabled`); optimistic `haveDesired`; 1.5 s `settle` busy on the switch | Same unit and optimistic flag (`service.setHostEnabled`); no busy/settle | partial | Same action; Omarchy switch shows busy until snapshot. |
| Certificate-mismatch banner | Panel text in `Panel.qml` | Same wording in `panel.tree()` | full | |
| Last ctl error line | `lastError` | Same (`snap.lastError`) | full | |
| Overview: idle facts | Devices paired / Pairing open\|closed / Host version (`sessionFacts`) | Same | full | Uses `summary.native_paired_clients` + `summary.version`. Neither shows `summary.conflicts` (see B). |
| Overview: live facts | Resolution, fps, bitrate, first-frame (`sessionFacts`) | Same | full | |
| Overview: desktop vs launched game | “No game was launched…” + game rows (`title`, `client`, `plane`, `grace`) | Same | full | |
| Stop the session / End the game | `sessionActions` → `ctl stop-session` / `end-game` | Same (`request("stop-session"|"end-game")`) | full | |
| Overview pillars + target sparkline | `statsPillars` + `SparkChart` on `history.target`; poll 2 s while open on Overview/Stats | Same (`ui.progress` / `ui.graph`; `ctl.shouldPollStats`) | full | Window 90 samples (~3 min). Cleared on `stream.stopped` / `session.ended`. |
| Pair: incoming Accept / Reject | Banner + buttons; `ctl approve\|deny <id>` | Same | full | Approve-by-id, never “newest” (`ctl.rs` `one_id`). |
| Pair: extra pending rows | `remainingPair` Accept / Reject | Same | full | |
| Pair: verify PIN while armed | Large PIN when `armed && pairingPin` | Same | full | |
| Pair: pairing-window toggle | `ctl pair arm` / `pair disarm` (no extra flags) | Same (`pair-arm` / `pair-disarm`) | full | Neither plugin passes `--ttl`, `--expires-in`, `--preset`, `--fingerprint`. |
| Pair: Moonlight PIN field | `PinRow` + `Model.pinArgs` → `ctl pin PIN UNIQUEID FP PEER_IP` | Same; Submit + `onSubmit`. `Return` not in `capture_keys` so Enter stays in the field | full | Omarchy blocks panel keys while `pinEditing`. |
| Pair empty / host stopped | “Start the host to open a pairing window.” | Same | full | |
| Pairing notification with Approve / Deny | **Not in QML.** `hooks/pairing-pending` → `omarchy-notification-send --exec "Approve:punktfunk-host ctl approve $id"` / Deny | `noctalia.notify("Punktfunk", "Pairing request from " .. name)` — title + name only, **no actions** (`service.refreshPending`) | partial | Biggest daily-use gap. Omarchy README: the plugin only updates the badge; the hook owns the toast. Noctalia has no host-hook package, so the in-plugin notify is the substitute and is weaker. |
| Stream started / stopped toasts | `hooks/stream-started`, `hooks/stream-stopped` via `omarchy-notification-send` | None | missing | Plugin already receives `stream.*` on the watch and refreshes; it does not notify. |
| Idle-while-streaming (stay awake) | `hooks/idle-guard` + `omarchy-toggle-idle` (`stream.started` / `stream.stopped`) | None | missing | Omarchy helper, not `ctl`. On lea this would need a Noctalia/NixOS idle inhibitor, not a port of `omarchy-toggle-idle`. |
| Devices: both planes, unpair confirm | Native + GameStream; Unpair → Confirm / Cancel; `y` / `c` | Same (`unpairFingerprint`, `capture_keys` `y`/`c`) | full | `ctl unpair <fingerprint>`. |
| Devices: show access_level | Read-only on the row (`device.access_level`) | Same | full | Neither calls `ctl access` to **change** it. |
| Devices: rename | No UI | None | missing (both) | Host has `ctl rename <fp> <name>`. |
| Display: Dedicated vs This screen | `punktfunk-omarchy mode dedicated\|mirror`; status via `mode --status` | Writes `display-settings.json` + strips `PUNKTFUNK_CAPTURE_MONITOR` from `host.env`, then `systemctl --user try-restart`; primary connector from `punktfunk-host list-monitors` (`ctl.primaryConnector`) | full* | Same contract files. *Omarchy helper also does Hyprland/firewall/menu work `setup` already did; Noctalia must not call `punktfunk-omarchy` (`test_contract.py`). Live resolution on the selected card is Omarchy-only (`Panel.qml` DisplayTab). |
| Display: policy rows | Topology / Identity / Mode clash / Max displays (`policyRows`) | Same | full | |
| Display: apply built-in + custom presets | `ctl display preset <id>` | Same | full | |
| Display: live / lingered heads | Deliberately **not** listed (plugin README; omarchy.mdx). Recovery is `ctl display release` | Same omission | full (intentional) | Verb unused by both — see recommendations. |
| Display keep-alive copy | Hyprland-specific caption | General compositor wording | partial | Copy only. |
| Stats: stream line, pillars, encoder, first frame | Width×height @ fps · codec; encoder_backend · gpu | Same | full | |
| Stats: record timings start/stop | `ctl stats record start\|stop`; charts Sent / fps / encode only while armed | Same | full | Shared one host-wide capture slot with the web console. |
| Keyboard: `1`–`5`, `h`/`l` tabs | `Keys.onPressed` + `onMoveRequested` | `plugin.toml` `capture_keys` + `panel.onKey` | full | |
| Keyboard: `j`/`k` cursor, Enter activate, Tab switch panels | `PanelKeyCatcher` `onMoveRequested` / `onActivateRequested` / `onTabRequested` | No cursor model; `j`/`k`/`Return` intentionally **not** captured so the PIN field works | missing | Click path is complete. Cursor is Omarchy chrome. |
| Keyboard: `x` deny focused pair; Esc closes | `Key_X` on incoming/pending; Esc via `onCloseRequested` (cancels unpair first) | `x` denies **incoming only** (not extra pending). Esc is host close | partial | |
| Console open | `omarchy-launch-webapp "$(punktfunk-host ctl console-url \|\| echo https://localhost:47992)"` | `ctl console-url` then `xdg-open`; fallback `https://localhost:47992` (`ctl.consoleUrlFromOutput`) | full | Same ticket verb; different launcher. `console-url` is Unix-only in `ctl.rs`. |
| Watch: one `ctl watch` | `Process` `argvFor(["watch","--kinds","pairing.*,stream.*,session.*,host.*"])`; retry 15 s from `runningChanged` | `runStream(ctl.watchCommand())` with quoted kinds; `processMatches` re-arm + 15 s (`WATCH_RETRY_MS`) | full | Same kind filter. Omarchy `ctl watch` reconnects internally; Noctalia also polls because `runStream` does not report a dead child. |
| Watch: `ctl.resync` re-snapshots | `refresh` + clients + displays | `refreshAll()` | full | |
| Watch: `ctl.disconnected` / `host.stopping` | Mark stopped, clear pairing | Same (`eventStopsHost`) | full | |
| Stats poll only while panel open on Overview/Stats | `statsPoll.running` | `ctl.shouldPollStats(panelOpen, panelTab, state)` | full | Host publishes no periodic stats (`Service.qml` comment; host-cli.md). |
| Plugin never HTTPS / never token | `Service.qml` is the only spawn site | `service.luau` is the only spawn site (`test_contract.py`) | full | |
| Tests | `Model.test.js` | `tests/test_{model,ctl}.luau`, `test_{contract,static}.py`, `scripts/selftest.sh` | full | Different harness, same model contract. |

\*Display-mode **outcome** is full; the Omarchy helper is richer (Hyprland wiring). Noctalia’s file write is the documented port.

---

## B. CLI / API inventory

### `punktfunk-host ctl` verbs

From `print_usage()` and `run()` in `crates/punktfunk-host/src/ctl.rs`, mirrored in `docs-site/content/docs/host-cli.md`. `--json` is a mode on every verb (envelope `{"v":1,"data"| "error"}`). Exit 4 = certificate pin mismatch.

| Verb | HTTP `ctl` actually calls (do not use from the plugin) | Omarchy plugin | Noctalia plugin | Neither |
| --- | --- | --- | --- | --- |
| `status` | `GET /api/v1/status` | yes | yes | |
| `sessions` | slice of `/api/v1/status` | no | no | **unused** (status already carries sessions/games/stream) |
| `summary` | `GET /api/v1/local/summary` | yes (name + version) | yes (same) | `conflicts`, `audio_streaming`, `paired_clients` (GameStream count), `pending_approvals` unused in UI |
| `watch [--kinds] [--since]` | `GET /api/v1/events?kinds=&since=` | kinds filter only | kinds filter only | `--since` unused (watch starts at live tail) |
| `pair status` | `GET /api/v1/native/pair` + `GET /api/v1/pair` | yes | yes | |
| `pair arm` | `POST /api/v1/native/pair/arm` | yes, no flags | yes | `--ttl`, `--expires-in`, `--preset`, `--fingerprint` unused |
| `pair disarm` | `DELETE /api/v1/native/pair` | yes | yes | |
| `pending` | `GET /api/v1/native/pending` | yes | yes | |
| `approve <ID>` | `POST /api/v1/native/pending/{id}/approve` | yes, id only | yes, id only | `--name`, `--preset`, `--expires-in` unused |
| `deny <ID>` | `POST /api/v1/native/pending/{id}/deny` | yes | yes | |
| `pin <PIN> <UNIQUEID> <FP> <PEER_IP>` | `POST /api/v1/pair/pin` | yes | yes | |
| `clients` | `GET /api/v1/native/clients` + `GET /api/v1/clients` | yes | yes | |
| `rename <FP> <NAME>` | `PATCH /api/v1/native/clients/{fp}` or `/api/v1/clients/{fp}` | no | no | **unused** |
| `access <FP> <full\|controller\|view>` | `PATCH /api/v1/native/clients/{fp}` `{grants}` | no | no | **unused** (row shows `access_level` only) |
| `unpair <FP>` | `DELETE` native then GameStream | yes | yes | |
| `unpair --all [--yes]` | `DELETE` both client collections | no | no | **unused** (correct: mass-destructive) |
| `stop-session` | `DELETE /api/v1/session` | yes | yes | |
| `end-game` | `POST /api/v1/game/end` | yes | yes | |
| `console-url` | **not HTTP** — writes a 0600 stub under `$XDG_RUNTIME_DIR` (`ctl.rs` `console_stub`) | yes | yes | Documented in `ctl` usage; **absent** from the host-cli.md verb table |
| `display` / `display status` | `GET /api/v1/display/settings` + `GET /api/v1/display/state` | yes (policy + presets; not live heads) | yes | `displays[]` (live/lingered heads) unused in UI by design |
| `display preset <ID>` | `PUT /api/v1/display/settings` (read-modify) | yes | yes | |
| `display release [SLOT]` | `POST /api/v1/display/release` | no | no | **unused** |
| `stats` | `/status` + `/stats/capture/status` + `/stats/capture/live` | yes | yes | |
| `stats record start\|stop` | `POST /api/v1/stats/capture/start\|stop` | yes | yes | |

`help` / `-h` exist. Unknown verbs print usage and exit 2.

### Related non-`ctl` commands the plugins spawn

| Command | Omarchy | Noctalia |
| --- | --- | --- |
| `systemctl --user start\|stop punktfunk-host.service` | yes | yes |
| `systemctl --user try-restart punktfunk-host.service` | via `punktfunk-omarchy mode` | yes, after writing display files |
| `punktfunk-host list-monitors` | no (helper does it) | yes, to pick primary connector |
| `punktfunk-omarchy mode …` | yes | **must not** |
| `omarchy-launch-webapp` | yes | no (`xdg-open`) |

Host-cli.md also documents `serve`, `list-monitors`, `openapi`, `detect-conflicts`, `library`, `plugins`, etc. Those are host-operator commands, not plugin surface. `detect-conflicts` is what fills `summary.conflicts`; the plugin already fetches `summary` and ignores that field.

### Watch event kinds

**Host kinds** (`EventKind::name()` in `crates/punktfunk-host/src/events.rs`):

| Kind | Domain |
| --- | --- |
| `client.connected`, `client.disconnected` | client |
| `session.started`, `session.ended` | session |
| `stream.started`, `stream.stopped` | stream |
| `game.running`, `game.window`, `game.exited` | game |
| `pairing.pending`, `pairing.completed`, `pairing.denied` | pairing |
| `access.granted`, `access.changed`, `access.expired` | access |
| `display.created`, `display.released` | display |
| `library.changed` | library |
| `update.available`, `update.applied` | update |
| `plugins.changed`, `store.changed` | plugins / store |
| `settings.changed` | settings |
| `action.invoked` | action (`power.sleep` / `reboot` / `shutdown` / `host.restart`) |
| `host.started`, `host.stopping` | host |

**Synthetic `ctl watch` kinds** (`ctl/watch.rs`): `ctl.resync` (SSE `dropped`), `ctl.disconnected`, `ctl.heartbeat` (~15 s SSE comment), plus pass-through of host `live` as `{"kind":"live"}`.

**Filter both plugins subscribe:** `pairing.*,stream.*,session.*,host.*` (`Service.qml` watcher `command`; `ctl.WATCH_KINDS`).

| Kind / pattern | Omarchy plugin | Noctalia plugin | Notes |
| --- | --- | --- | --- |
| `pairing.completed`, `pairing.denied`, `host.started` | special-cased: refresh + clients | same (`eventNeedsClients`) | |
| `pairing.pending` | refresh only (badge); toast is the **hook** | refresh + in-plugin notify if pending count rose | Noctalia notify is count-based, not kind-based |
| `host.stopping`, `ctl.disconnected` | stop + clear pairing | same | |
| `stream.stopped`, `session.ended` | `clearHistory()` then refresh | same (`eventClearsHistory`) | |
| `stream.started`, `session.started`, other matching kinds | generic `refresh()` | same | |
| `ctl.resync` | refresh + clients + displays | `refreshAll()` | |
| `ctl.heartbeat` | ignored (no `kind` handler) | ignored (`eventKind` returns it; no branch) | Correct — keep-alive only |
| `game.*` | **not subscribed** | **not subscribed** | Panel games list updates only via `status` after a subscribed event |
| `access.*`, `display.*`, `client.*`, `library.*`, `update.*`, `plugins.*`, `store.*`, `settings.*`, `action.*` | not subscribed | not subscribed | |

Omarchy **hooks** (not the QML plugin) consume `pairing.pending`, `stream.started`, `stream.stopped` via `~/.config/punktfunk/hooks.json`. That is host automation (`automation.md`), still `ctl` for Approve/Deny.

### Management HTTP (docs only)

`docs-site/content/docs/host-cli.md` (`serve` / `ctl` / How it authenticates) and `docs-site/content/docs/automation.md` (`GET /api/v1/events`): admin surface is HTTPS + bearer token, **loopback only**. `ctl` reads `mgmt-token` and pins `native-cert.pem` before sending. Plugins must not `curl` this. `punktfunk-host openapi` prints the document; this audit did not dump it.

---

## C. Ranked next features (Noctalia)

Skip: cursor `j`/`k`/Enter, LensMark canvas, phrase fade, Hyprland-only copy, `unpair --all`, `watch --since`, idle-guard (needs a Noctalia idle API, not `omarchy-toggle-idle`).

Keep using `punktfunk-host ctl` only.

1. **Actionable pairing notification (closes the real Omarchy gap)**  
   Omarchy’s daily “a device is knocking” path is the hook toast with Approve / Deny **by id**. Noctalia’s `noctalia.notify` is name-only and has no actions; Accept/Reject live only on the Pair tab. If `noctalia.notify` can attach actions, spawn `ctl approve|deny <id>` through the existing `request` bus. If it cannot, at least include the fingerprint tail (Omarchy body: name + `…tail`) and open the Pair tab / panel on click. Wire off `pairing.pending` (or keep the pending-count edge) so two devices cannot approve the wrong id.

2. **Change access level from Devices (`ctl access`)**  
   Both plugins already show `access_level`. The console’s full / controller / view chip is unused ctl headroom (`access.rs` presets `full|controller|view`). High-value on a shared host; no new protocol. Optional sibling: `ctl rename` on the same row.

3. **Surface `summary.conflicts`**  
   `ctl summary` is already polled. `render_summary` prints competing Moonlight-compatible hosts. Neither plugin shows `conflicts[]`. A one-line Overview / stopped banner (“Sunshine is also bound on this box”) is the cheapest diagnosis for “pairing / ports look dead” and uses data already in `snap.summary`.

4. **Release kept displays (`ctl display release`)**  
   Both UIs refuse to list live heads (correct). The missing recovery control is Release — the same action omarchy.mdx tells operators to run when Exclusive + keep-alive leaves physical screens dark. A Display-tab button that calls `display release` (no slot = all kept) is the ctl verb that exists for that job. Confirm copy: never touches an actively streaming head (`ctl.rs`).

5. **Stream start/stop notifications (optional, lower than 1–4)**  
   Omarchy ships `stream-started` / `stream-stopped` toasts (who, mode, HDR, app). The watch already includes `stream.*`. A quiet Noctalia notify on those kinds matches packaging without new verbs. Do not also toast from the pairing hook path twice.

### Headroom explicitly not ranked

- `pair arm --fingerprint` / `--preset` — useful for locked pairing; niche vs (1).  
- `approve --name/--preset` — same; first-approve defaults are enough if (2) exists.  
- Subscribing to `game.*` — Overview already lists games from `status` after session/stream events; extra kinds help only if game-window timing should change the UI.  
- `ctl sessions` — redundant with `status`.
