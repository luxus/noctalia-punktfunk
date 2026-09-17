# Changelog

## Unreleased

- Pairing toast includes the fingerprint tail and opens the Pair tab on bar click. `noctalia.notify` cannot attach Approve/Deny actions (plugin_api 24 is title+body only); Accept/Reject stay on the Pair tab, by pending id.
- Devices: `ctl access` (`full` / `controller` / `view`) and `ctl rename`.
- Overview / panel banner surfaces `summary.conflicts[]`.
- Display: `ctl display release` for kept heads (copy: never an actively streaming head).
- Stream start/stop toasts from `stream.*` watch kinds.
- Bar pending-count badge, streaming pip, and fill/border around `punktfunk-logo.svg` (logo agent vendors the SVG; this plugin does not). Glyph fallback until that file lands.
- Hero shows the live codec; host toggle is busy for 1.5s until the snapshot settles.
- Quote `ctl watch` kinds for `runStream` (shell string; `*` must not glob).
- Re-arm a dead watcher with `processMatches` and a 15s backoff.
- Drop `Return` / `j` / `k` from panel `capture_keys` so the Moonlight PIN field keeps Enter.

## 0.1.0

First Noctalia v5 Luau port of the Punktfunk Omarchy bar plugin.

- Bar widget, panel, service, and control-center shortcut (`luxus/punktfunk`)
- Host status, pairing, devices, display mode/presets, and session stats
- Every host call is `punktfunk-host ctl` (plugin_api 24 argv form). The plugin never speaks HTTPS and never holds the operator token.
