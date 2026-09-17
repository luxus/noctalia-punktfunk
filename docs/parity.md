# Omarchy vs Noctalia plugin parity

Feature-parity of the Noctalia plugin (`luxus/punktfunk` in this repo) against the Omarchy/Quickshell plugin, plus unused `punktfunk-host ctl` / watch surface.

Updated after closing the ranked ctl-only gaps. The plugin still never speaks HTTPS and never holds the operator token.

## Sources (verified against files)

| Tree | Ref | What was read |
| --- | --- | --- |
| Omarchy plugin + helpers | [`luxus/punktfunk`](https://github.com/luxus/punktfunk) `@3897a989d7d64e676aed13ae762a8a9806eb8743` | `packaging/linux/omarchy/plugin/{Panel.qml,Service.qml,Model.js,README.md,manifest.json}`, `packaging/linux/omarchy/hooks/*`, `packaging/linux/omarchy/punktfunk-omarchy` |
| Noctalia plugin | this repo (`luxus/noctalia-punktfunk`) | `punktfunk/{panel,service,model,widget,shortcut,ctl}.luau`, `plugin.toml`, `README.md` |
| Host CLI / events | same punktfunk checkout | `crates/punktfunk-host/src/ctl.rs`, `ctl/watch.rs`, `events.rs` (`EventKind`), `docs-site/content/docs/host-cli.md`, `docs-site/content/docs/automation.md` |
| Noctalia runtime | plugin_api 24 docs + `noctalia.d.luau` | `noctalia.notify(title, body)` is title+body only — no actions, no click handler |

Trust boundary (both plugins, host docs): the plugin must keep using `punktfunk-host ctl` only. It must not speak HTTPS, hold the operator token, or see the host certificate. HTTP paths below are the routes `ctl` itself calls; they are **not** a plugin API.

Status key: **full** = same user-visible capability; **partial** = same intent, missing a control or cue; **missing** = Omarchy (plugin or its shipped hooks/helper) has it, Noctalia does not; **noctalia-only** = Noctalia has it, Omarchy plugin does not; **blocked** = attempted, host API cannot do it.

---

## A. Parity matrix

Rows are user-visible capabilities from the Omarchy bar plugin and the hooks `punktfunk-omarchy setup` installs next to it.

| Capability | Omarchy | Noctalia | Status | Notes |
| --- | --- | --- | --- | --- |
| Bar: stopped / idle / streaming | Two-ring `LensMark`; filled while streaming, dim when stopped | Brand mark is vendored `punktfunk-logo.svg` (also `assets/punktfunk-logo.svg`). Fallback glyph if missing. Streaming = `primary` fill/border + pip around the mark | full | Overlay, not a replacement. `model.widgetLogoPath` / `model.LOGO_PATH`. `TODO(bc-e0bdb3f3)` in `widget.luau`. |
| Bar: device waiting | Urgent colour **and** corner badge | Error fill/border **around the logo** plus pending-count badge; tooltip `widget.pending` | full | Click opens the Pair tab (`focusPair`). Logo stays the mark. |
| Bar: certificate pin mismatch (ctl exit 4) | Warning glyph, urgent colour | Error chrome around the logo plus a small `alert-triangle` overlay (logo is not swapped out). Tooltip `widget.pin_mismatch` | full | Same distinction from “host down”. |
| Click opens panel | left-click → `root.toggle()` | `widget.onClick` → `noctalia.togglePanel("luxus/punktfunk:panel")`; waiting pair also sets `focusPair` | full | |
| Right-click: stop session or open console | Streaming → `ctl stop-session`; else `openConsole()` | Same split (`widget.onRightClick`) | full | |
| Bar tooltip / label | Implicit via mark + panel | Tooltips in `translations/en.json`; optional `show_label` | noctalia-only | |
| Control-center / shortcut tile | Omarchy IPC | `shortcut.luau` tile | noctalia-only | |
| Panel: five tabs | Overview / Pair / Devices / Display / Stats | Same (`model.TAB_IDS`) | full | |
| Tab badge: Pair · N | `tabLabel(id, pending)` | Same | full | |
| Waiting pair focuses Pair tab | `needsYou` → pair | Same, plus `focusPair` from the pairing toast / bar click | full | |
| Hero: title / rotating phrases / host toggle | phrases + toggle; 2800 ms fade | Same phrases and toggle; phrase swap without fade | partial | Animation is Omarchy-only (skipped). |
| Hero: live codec | `PanelHero.detail` = `stream.codec` | `model.heroDetail` in the header | full | |
| Host start / stop | `systemctl --user start\|stop`; optimistic `haveDesired`; 1.5 s `settle` busy | Same unit, optimistic flag, `hostBusy` + `ctl.HOST_SETTLE_MS` (1500) disables the toggle until snapshot | full | |
| Certificate-mismatch banner | Panel text | Same wording in `panel.tree()` | full | |
| Last ctl error line | `lastError` | Same | full | |
| Overview: idle facts | Devices paired / Pairing / Host version | Same | full | |
| Overview: `summary.conflicts[]` | Unused | Panel banner (`model.conflictBanner`) on every tab, including stopped host | noctalia-only | e.g. `Sunshine (running) is also bound on this box`. |
| Overview: live facts | Resolution, fps, bitrate, first-frame | Same | full | |
| Overview: desktop vs launched game | Same copy | Same | full | |
| Stop the session / End the game | `ctl stop-session` / `end-game` | Same | full | |
| Overview pillars + target sparkline | 2 s poll on Overview/Stats | Same (`ctl.shouldPollStats`) | full | |
| Pair: incoming Accept / Reject | `ctl approve\|deny <id>` | Same, by id, never “newest” | full | |
| Pair: extra pending rows | remaining Accept / Reject | Same | full | |
| Pair: verify PIN / arm toggle / Moonlight PIN | Same ctl verbs | Same | full | |
| Pairing notification with Approve / Deny | Hook toast `--exec` Approve/Deny **by id** | In-plugin `noctalia.notify` with name + fingerprint tail; **no actions** (API is title+body only). Bar click / `focusPair` opens the Pair tab, where Accept/Reject run `ctl approve\|deny <id>`. Toasts keyed by pending id. | partial / blocked | Documented limitation. Closest substitute the runtime allows. |
| Stream started / stopped toasts | `hooks/stream-started`, `stream-stopped` | `noctalia.notify` on `stream.started` / `stream.stopped` (client · mode · HDR · app) | full | Quiet; does not double-toast pairing. |
| Idle-while-streaming (stay awake) | `hooks/idle-guard` + `omarchy-toggle-idle` | None | missing | Deferred. Needs a Noctalia/NixOS idle inhibitor, not a port of `omarchy-toggle-idle`. |
| Devices: both planes, unpair confirm | Native + GameStream; `y` / `c` | Same | full | |
| Devices: change `access_level` | Read-only | `ctl access <fp> <full\|controller\|view>` chips on native rows | noctalia-only | |
| Devices: rename | No UI | `ctl rename <fp> <name>` on native rows | noctalia-only | |
| Display: Dedicated vs This screen | helper `mode` | Writes `display-settings.json` / `host.env`, `try-restart`; **must not** call `punktfunk-omarchy` | full* | |
| Display: policy + presets | Same | Same | full | |
| Display: live / lingered heads listed | Deliberately not listed | Same omission | full (intentional) | |
| Display: release kept heads | unused (docs tell you to run ctl) | Display-tab **Release kept displays** → `ctl display release` (no slot = all kept). Copy: never touches an actively streaming head. | noctalia-only | |
| Stats: stream line, pillars, encoder, capture | Same | Same | full | |
| Keyboard: `1`–`5`, `h`/`l` tabs | Same | Same | full | |
| Keyboard: `j`/`k` cursor, Enter activate | Omarchy chrome | Intentionally not captured (PIN field) | missing | Deferred. Click path is complete. |
| Keyboard: `x` deny focused pair; Esc closes | `x` on incoming/pending | `x` denies incoming only. Esc is host close | partial | Deferred (PIN / cursor conflict). |
| Console open | `omarchy-launch-webapp` + `ctl console-url` | `ctl console-url` then `xdg-open` | full | |
| Watch: one `ctl watch` | same kinds | same kinds, quoted; `processMatches` re-arm | full | |
| Plugin never HTTPS / never token | Service is only spawn site | `service.luau` is the only spawn site | full | |
| Tests | `Model.test.js` | `tests/test_{model,ctl}.luau`, `test_{contract,static}.py`, `scripts/selftest.sh` | full | |

\*Display-mode **outcome** is full; the Omarchy helper is richer (Hyprland wiring). Noctalia’s file write is the documented port.

---

## B. CLI / API inventory

### `punktfunk-host ctl` verbs

`--json` envelope `{"v":1,"data"|"error"}`. Exit 4 = certificate pin mismatch.

| Verb | Omarchy plugin | Noctalia plugin | Notes |
| --- | --- | --- | --- |
| `status` | yes | yes | |
| `sessions` | no | no | unused (status already carries sessions/games/stream) |
| `summary` | name + version | name + version + **`conflicts[]`** + `kept_displays` | |
| `watch [--kinds]` | kinds filter | kinds filter | `--since` unused |
| `pair status` / `arm` / `disarm` | yes, no extra flags | yes | |
| `pending` | yes | yes | |
| `approve <ID>` / `deny <ID>` | yes, id only | yes, id only | toast cannot attach these; Pair tab can |
| `pin …` | yes | yes | |
| `clients` | yes | yes | |
| `rename <FP> <NAME>` | no | **yes** | Devices tab |
| `access <FP> <full\|controller\|view>` | no | **yes** | Devices tab chips |
| `unpair <FP>` | yes | yes | |
| `unpair --all [--yes]` | no | no | unused on purpose (mass-destructive) |
| `stop-session` / `end-game` | yes | yes | |
| `console-url` | yes | yes | |
| `display` / `display preset` | yes | yes | live heads unused in UI by design |
| `display release [SLOT]` | no | **yes** (no slot = all kept) | |
| `stats` / `stats record start\|stop` | yes | yes | |

### Watch event kinds

Filter: `pairing.*,stream.*,session.*,host.*`.

| Kind / pattern | Noctalia | Notes |
| --- | --- | --- |
| `pairing.pending` | refresh + **per-id toast** + `focusPair` | No longer count-edge only |
| `pairing.completed`, `pairing.denied`, `host.started` | refresh + clients | |
| `host.stopping`, `ctl.disconnected` | stop + clear pairing | |
| `stream.started` | refresh + toast | |
| `stream.stopped`, `session.ended` | clear history + refresh; toast on `stream.stopped` | |
| `ctl.resync` | `refreshAll()` | |
| `ctl.heartbeat` | ignored | keep-alive |
| `game.*`, `access.*`, `display.*`, … | not subscribed | |

---

## C. Ranked next features — closed / deferred

Keep using `punktfunk-host ctl` only.

| # | Item | Status |
| --- | --- | --- |
| 1 | Actionable pairing notification (Approve/Deny by id) | **Shipped substitute.** `noctalia.notify` cannot attach actions (evidence: plugin_api 24 / `noctalia.d.luau` `notify: (title, body?)`). Toast includes fingerprint tail; bar click + `focusPair` open the Pair tab; Accept/Reject still `ctl approve\|deny <id>`. |
| 2 | Devices: `ctl access` + `ctl rename` | **Shipped.** Native-plane chips + rename field. |
| 3 | Surface `summary.conflicts[]` | **Shipped.** Panel banner. |
| 4 | `ctl display release` for kept heads | **Shipped.** Display tab; copy states it never releases an actively streaming head. |
| 5 | Stream start/stop toasts | **Shipped.** From `stream.*` watch kinds. |
| — | Bar pending badge / clearer streaming state | **Shipped.** Badge + streaming pip + fill/border **around** vendored `punktfunk-logo.svg`. |
| — | Hero live codec + host-toggle busy/settle | **Shipped.** |

### Deferred (not trivial / out of scope)

- Omarchy `j`/`k`/Enter cursor model — PIN field conflict; click path is complete.
- Idle-guard / `omarchy-toggle-idle` — not `ctl`; needs a Noctalia idle inhibitor.
- `unpair --all` — mass-destructive; leave unused.
- `watch --since`, `pair arm --fingerprint/--preset`, `approve --name/--preset`, `game.*` subscription, LensMark canvas, phrase fade.

---

## D. `noctalia.notify` action capabilities (plugin_api 24)

Verified against [Runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/) and `noctalia-dev/official-plugins` `noctalia.d.luau`:

| Call | Signature | Actions | Click / `onActivate` | Urgency / icon |
| --- | --- | --- | --- | --- |
| `noctalia.notify` | `(title: string, body: string?) -> ()` | **none** | **none** | none |
| `noctalia.notifyError` | `(title: string, body: string?) -> ()` | **none** | **none** | error styling only |

There is no third argument, no `actions` / `--exec` table, and no notification-click callback. Omarchy’s pairing toast with `Approve:punktfunk-host ctl approve $id` cannot be reproduced through this API.

**What this plugin does instead**

- Pairing: `noctalia.notify("Punktfunk pairing request", "<name> wants to pair · …tail — open the Pair tab…")`, keyed by pending id. Bar click sets `focusPair` and opens the Pair tab; Accept/Reject there call `ctl approve\|deny <id>`.
- Stream: `noctalia.notify` on `stream.started` / `stream.stopped` (title + body only).
- The plugin does **not** shell out to `notify-send` or `omarchy-notification-send` to fake actions (would bypass the request bus and duplicate toasts).
