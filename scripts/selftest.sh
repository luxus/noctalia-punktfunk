#!/usr/bin/env bash
# Structural + Luau checks. No Noctalia session and no Punktfunk host required.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

python3 -m unittest discover -s punktfunk/tests -v

concat_and_run() {
  local module="$1"
  local tests="$2"
  local out="$3"
  python3 - "$module" "$tests" "$out" <<'PY'
from pathlib import Path
import sys
mod = Path(sys.argv[1]).read_text()
needle = "return " + Path(sys.argv[1]).stem
if not mod.rstrip().endswith(needle):
    raise SystemExit(f"{sys.argv[1]} must end with {needle}")
body = mod.rstrip()[: -len(needle)].rstrip() + "\n"
Path(sys.argv[3]).write_text(body + "\n" + Path(sys.argv[2]).read_text())
PY
  "$LUAU" "$out"
}

LUAU="${LUAU:-}"
if [[ -z "$LUAU" ]]; then
  if command -v luau >/dev/null 2>&1; then
    LUAU="$(command -v luau)"
  elif [[ -x /tmp/luau-bin/luau ]]; then
    LUAU=/tmp/luau-bin/luau
  fi
fi

COMPILER="${LUAU_COMPILE:-}"
if [[ -z "$COMPILER" ]]; then
  if command -v luau-compile >/dev/null 2>&1; then
    COMPILER="$(command -v luau-compile)"
  elif [[ -x /tmp/luau-bin/luau-compile ]]; then
    COMPILER=/tmp/luau-bin/luau-compile
  fi
fi

if [[ -n "$COMPILER" ]]; then
  for f in punktfunk/*.luau; do
    "$COMPILER" --binary "$f" >/dev/null
  done
  echo "luau-compile: ok"
else
  echo "luau-compile not on PATH; skipping syntax compile"
fi

if [[ -n "$LUAU" ]]; then
  concat_and_run punktfunk/model.luau punktfunk/tests/test_model.luau /tmp/punktfunk-model-check.luau
  concat_and_run punktfunk/ctl.luau punktfunk/tests/test_ctl.luau /tmp/punktfunk-ctl-check.luau
else
  echo "luau not on PATH; skipping model/ctl runtime checks"
fi
