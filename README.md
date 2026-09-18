# noctalia-punktfunk

Noctalia v5 plugin for the [Punktfunk](https://punktfunk.com) host on **lea** (NixOS). Watch the live session, pair a device, and stop a stream from the bar — without opening a browser.

Ported from the Omarchy/Quickshell plugin in [luxus/punktfunk](https://github.com/luxus/punktfunk) (`packaging/linux/omarchy/plugin/`) to Noctalia v5 Luau (`plugin_api` 24). This is a **standalone** plugin repository. It must not land inside `luxus/punktfunk`.

Plugin id: **`luxus/punktfunk`**. Noctalia catalogs plugins as `author/name`, and this repo’s plugin directory is `punktfunk/` so it matches the id after the slash — same pattern as `luxus/elgato-control`.

Requires Noctalia v5 with plugin API 24 (v5.0.0-beta.9 or newer). `plugin_api` replaced `min_noctalia`; 24 is the compatibility gate.

Not affiliated with Noctalia beyond using its plugin API. Darwin / macOS are out of scope.

## What it shows

- **Bar widget** — official lens mark (`assets/punktfunk-mark.svg`, no wordmark), otherwise a cast glyph. Semantic fill/border, a primary pip while streaming, and a pending-count badge wrap the mark rather than replacing it. Optional `show_label` draws "Punktfunk" as text next to the mark. Click opens the panel (Pair tab if something is waiting). Right-click stops a live session, or opens the web console when nothing is streaming.
- **Panel** — hero with the full lockup (`assets/punktfunk-logo.svg`, lens + wordmark) at a readable size, host start/stop (busy until the snapshot settles), and the live codec while streaming, then five tabs:
  - *Overview* — facts (including Encode/codec), competing-host banner from `summary.conflicts`, stop / end-game, bitrate / frames / encode pillars, and a target sparkline.
  - *Pair* — incoming request with Accept / Reject by pending id, the pairing PIN to verify, Moonlight PIN field, and the pairing-window toggle.
  - *Devices* — both planes; access `full` / `controller` / `view` (`ctl access`); rename (`ctl rename`); Unpair asks Confirm / Cancel (`y` / `c` while focused).
  - *Display* — Dedicated / This screen cards, policy, presets, and **Release kept displays** (`ctl display release`; never an actively streaming head).
  - *Stats* — the same pillars, encoder detail, and capture charts.
- **Service** — one long-lived `punktfunk-host ctl watch` stream that drives the widget and panel. `pairing.pending` raises a Noctalia notification with the claimed name and fingerprint tail; `stream.started` / `stream.stopped` raise quiet toasts.

`noctalia.notify(title, body)` and `noctalia.notifyError(title, body)` take two strings and nothing else: **no actions, no click handler, no urgency flag** (plugin_api 24). Approve / Deny therefore stay on the Pair tab, keyed by pending id. Click the bar widget to open that tab.
- **Shortcut** — control-center tile that opens the same panel.

Keyboard while the panel is focused: `1`–`5` and `h` / `l` switch tabs. A waiting pair opens the Pair tab. Escape closes (host behavior).

## Install on lea

Add this repo as a plugin source, then enable it:

```bash
noctalia msg plugins source add punktfunk git https://github.com/luxus/noctalia-punktfunk
noctalia msg plugins enable luxus/punktfunk
```

From a local checkout (highest precedence):

```bash
noctalia msg plugins source add punktfunk path /path/to/this/repo
noctalia msg plugins enable luxus/punktfunk
```

Add the **Punktfunk** bar widget in Noctalia settings. Click it (or the control-center tile) to open the panel.

The bar loads `assets/punktfunk-mark.svg` (lens only). The panel hero loads `assets/punktfunk-logo.svg` (lens + wordmark; also at plugin-relative `punktfunk-logo.svg`). Catalog listings and the control-center tile still use the Material `cast` glyph because `plugin.toml` `icon` and `shortcut.setIcon` only accept a Tabler/Material name. Overlay chrome (streaming fill, pending badge) wraps the bar mark. Confirm both on lea: this repo’s selftest does not drive a live Noctalia session.

## Requirements

A Punktfunk **host** on the same machine — `punktfunk-host` on `PATH`. The plugin talks to the host the same way the Omarchy plugin did:

| Call | Used for |
| --- | --- |
| `punktfunk-host ctl status \| pending \| pair status \| summary \| clients \| display \| stats --json` | Snapshots |
| `punktfunk-host ctl watch --kinds pairing.*,stream.*,session.*,host.*` | Event stream |
| `punktfunk-host ctl approve \| deny \| pin \| unpair \| access \| rename \| stop-session \| end-game` | Pairing, devices, and session |
| `punktfunk-host ctl display preset <id>` | Display presets |
| `punktfunk-host ctl display release` | Tear down kept (not streaming) virtual heads |
| `punktfunk-host ctl stats record start \| stop` | Frame-timing capture |
| `punktfunk-host ctl console-url` | One-shot web console ticket |
| `systemctl --user start \| stop punktfunk-host.service` | Host toggle |
| `punktfunk-host list-monitors` plus `~/.config/punktfunk/display-settings.json` | Dedicated vs This screen |

Every management call is `punktfunk-host ctl`. **The plugin never speaks HTTPS, never holds the operator token, and never sees the host’s certificate.** `ctl` reads the token and certificate from the 0700 config directory in its own process, pins the certificate before sending the token, and prints JSON on stdout. Exit 4 is a certificate mismatch: something that is not your host answered on the management port, and no credential was transmitted.

`service.luau` is the only spawn site. Panel and widget publish a `request` on `noctalia.state`; the service runs it.

Display mode does **not** call `punktfunk-omarchy`. That helper is Omarchy/Hyprland wiring. This plugin writes the same `display-settings.json` / `host.env` contract the helper uses, then `systemctl --user try-restart punktfunk-host.service`.

## How it talks to the host

One process runs continuously: `ctl watch`, in `service.luau`. Exactly one, because the host caps concurrent event streams and the web console holds one of them. `ctl.resync` re-snapshots rather than trusting a stale view. `runStream` is a shell string (the plugin_api 24 argv form is `runAsync` only), so the watch kinds are single-quoted to stop `pairing.*` from globbing. `runStream` does not report a dead child; the service re-arms the watcher with `processMatches`, with a 15s backoff like the Omarchy plugin.

The host publishes no periodic stats, so the sparkline polls `ctl stats` every two seconds, and **only** while Overview or Stats is the open tab. Everything else is event-driven or refreshed on open.

## Tests

No live Noctalia session or Punktfunk host is required:

```bash
python3 -m unittest discover -s punktfunk/tests -v
./scripts/selftest.sh
```

`selftest.sh` also compiles the Luau entries and runs `model` / `ctl` checks when `luau` / `luau-compile` are on `PATH`.

## Reversing it

```bash
noctalia msg plugins disable luxus/punktfunk
```

The plugin owns no host state — removing it changes nothing about your host, pairings, or firewall.

## Licence

MIT OR Apache-2.0, same as Punktfunk.
