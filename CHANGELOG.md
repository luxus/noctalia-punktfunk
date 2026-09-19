# Changelog

## Unreleased

- Stats **Download** exports `journalctl --user -u punktfunk-host.service` to a local file and opens the folder. Host `ctl` has no logs verb; the plugin does not call the HTTPS log API.
- Encode timings (ENCODE pillar, Encode p99 chart) show only while `ctl stats record` is armed. Recording shows a **Recording performance…** banner with Stop.
- Overview stop / end-game actions use the compact `sm` control size (they were full-width).
- Panel copy is English: **HDR (connected)** / **Chroma (connected)** (`yes`/`no`), Display **HDR allowed** / **4:4:4 allowed**.
- Pairing toast includes the fingerprint tail and opens the Pair tab on bar click. `noctalia.notify` cannot attach Approve/Deny actions (plugin_api 24 is title+body only); Accept/Reject stay on the Pair tab, by pending id.
- Devices: `ctl access` (`full` / `controller` / `view`) and `ctl rename`.
- Overview / panel banner surfaces `summary.conflicts[]`.
- Display: `ctl display release` for kept heads (copy: never an actively streaming head).
- Stream start/stop toasts from `stream.*` watch kinds.
- Vendor official `punktfunk-logo.svg` (and `assets/punktfunk-logo.svg`) as the bar and panel mark. Pending-count badge, streaming pip, and fill/border wrap it; glyph is the missing-file fallback.
- Hero shows the live codec; host toggle is busy for 1.5s until the snapshot settles.
- Display: **HDR allowed** / **4:4:4 allowed** write `PUNKTFUNK_10BIT` / `PUNKTFUNK_444` in `host.env` (next session; client still picks). Overview, hero and Stats show live **HDR (connected)** / **Chroma (connected)** from `ctl status`/`stats`/stream (`yes`/`no`/`4:4:4`/`4:2:0`, or `—`).
- Quote `ctl watch` kinds for `runStream` (shell string; `*` must not glob).
- Re-arm a dead watcher with `processMatches` and a 15s backoff.
- Drop `Return` / `j` / `k` from panel `capture_keys` so the Moonlight PIN field keeps Enter.

## 0.1.0

First Noctalia v5 Luau port of the Punktfunk Omarchy bar plugin.

- Bar widget, panel, service, and control-center shortcut (`luxus/punktfunk`)
- Host status, pairing, devices, display mode/presets, and session stats
- Every host call is `punktfunk-host ctl` (plugin_api 24 argv form). The plugin never speaks HTTPS and never holds the operator token.
