#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
if [[ -z "${cmd}" ]]; then
  echo "Usage: $0 {push|pop|reset|show|hide} [args...]" >&2
  exit 1
fi
shift || true

resolve_hs_bin() {
  local configured="${HS_BIN:-}"
  if [[ -n "${configured}" && -x "${configured}" ]]; then
    printf "%s" "${configured}"
    return 0
  fi

  if command -v hs >/dev/null 2>&1; then
    command -v hs
    return 0
  fi

  local candidate
  for candidate in /opt/homebrew/bin/hs /usr/local/bin/hs; do
    if [[ -x "${candidate}" ]]; then
      printf "%s" "${candidate}"
      return 0
    fi
  done

  return 1
}

HS_BIN="$(resolve_hs_bin || true)"
if [[ -z "${HS_BIN}" ]]; then
  echo "hs CLI not found. Install it in Hammerspoon Preferences -> Install Command Line Tool." >&2
  exit 127
fi

run_hs() {
  "${HS_BIN}" -c "${1}"
}

lua_escape() {
  local input="${1:-}"
  input="${input//\\/\\\\}"
  input="${input//\'/\\\'}"
  input="${input//$'\n'/\\n}"
  printf "%s" "$input"
}

case "${cmd}" in
  push)
    mode="${1:-}"
    options="${2:-}"
    run_hs "require('skhd_hud').push('$(lua_escape "${mode}")','$(lua_escape "${options}")')"
    ;;
  pop)
    run_hs "require('skhd_hud').pop()"
    ;;
  reset)
    run_hs "require('skhd_hud').reset()"
    ;;
  show)
    run_hs "require('skhd_hud').show()"
    ;;
  hide)
    run_hs "require('skhd_hud').hide()"
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    exit 1
    ;;
esac
