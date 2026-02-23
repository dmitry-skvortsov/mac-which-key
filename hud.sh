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

resolve_hud_module_path() {
  local configured="${SKHD_HUD_MODULE_PATH:-}"
  if [[ -n "${configured}" && -f "${configured}" ]]; then
    printf "%s" "${configured}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  local colocated_candidate="${script_dir}/skhd_hud.lua"
  if [[ -f "${colocated_candidate}" ]]; then
    printf "%s" "${colocated_candidate}"
    return 0
  fi

  local repo_hammerspoon_candidate="${script_dir}/.hammerspoon/skhd_hud.lua"
  if [[ -f "${repo_hammerspoon_candidate}" ]]; then
    printf "%s" "${repo_hammerspoon_candidate}"
    return 0
  fi

  local hammerspoon_candidate="${script_dir}/../../.hammerspoon/skhd_hud.lua"
  if [[ -f "${hammerspoon_candidate}" ]]; then
    printf "%s" "${hammerspoon_candidate}"
    return 0
  fi

  local home_candidate="${HOME}/.hammerspoon/skhd_hud.lua"
  if [[ -f "${home_candidate}" ]]; then
    printf "%s" "${home_candidate}"
    return 0
  fi

  return 1
}

HS_BIN="$(resolve_hs_bin || true)"
if [[ -z "${HS_BIN}" ]]; then
  echo "hs CLI not found. Install it in Hammerspoon Preferences -> Install Command Line Tool." >&2
  exit 127
fi

HUD_MODULE_PATH="$(resolve_hud_module_path || true)"
if [[ -z "${HUD_MODULE_PATH}" ]]; then
  echo "skhd_hud.lua not found. Set SKHD_HUD_MODULE_PATH or place it next to hud.sh (repo root), in ../../.hammerspoon (from skhd config), or ~/.hammerspoon." >&2
  exit 1
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

run_module_call() {
  local call="${1}"
  local escaped_module_path
  escaped_module_path="$(lua_escape "${HUD_MODULE_PATH}")"

  run_hs "local path='${escaped_module_path}'; local module=package.loaded['skhd_hud']; local currentPath=rawget(_G,'__skhd_hud_module_path'); if module~=nil and currentPath~=nil and currentPath~=path then package.loaded['skhd_hud']=nil; module=nil; end; if module==nil then local loader,err=loadfile(path); if not loader then error(err) end; local loaded=loader(); if type(loaded)~='table' then error('skhd_hud module must return a table') end; package.loaded['skhd_hud']=loaded; module=loaded; end; _G.__skhd_hud_module_path=path; module.${call}"
}

case "${cmd}" in
  push)
    mode="${1:-}"
    options="${2:-}"
    run_module_call "push('$(lua_escape "${mode}")','$(lua_escape "${options}")')"
    ;;
  pop)
    run_module_call "pop()"
    ;;
  reset)
    run_module_call "reset()"
    ;;
  show)
    run_module_call "show()"
    ;;
  hide)
    run_module_call "hide()"
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    exit 1
    ;;
esac
