# Changelog

## Unreleased

- Quote `ctl watch` kinds for `runStream` (shell string; `*` must not glob).
- Re-arm a dead watcher with `processMatches` and a 15s backoff.
- Drop `Return` / `j` / `k` from panel `capture_keys` so the Moonlight PIN field keeps Enter.

## 0.1.0

First Noctalia v5 Luau port of the Punktfunk Omarchy bar plugin.

- Bar widget, panel, service, and control-center shortcut (`luxus/punktfunk`)
- Host status, pairing, devices, display mode/presets, and session stats
- Every host call is `punktfunk-host ctl` (plugin_api 24 argv form). The plugin never speaks HTTPS and never holds the operator token.
