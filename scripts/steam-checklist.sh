#!/usr/bin/env bash
# M2 exit checklist for Steam: install -> login -> install game -> launch -> quit -> relaunch.
#
# Automates what can be automated and checks the rest. Login and the game install are done by
# a person (this script never handles credentials); it waits for you, then verifies the result.
# Run it on each macOS version you want to claim support for and keep the report.
#
#   scripts/steam-checklist.sh --app 3480990 --game-process 'orcs\.exe' [--bottle NAME]
#
# Options:
#   --bottle NAME        bottle to use (default: steam-checklist). Created if missing; an existing
#                        bottle with Steam already installed skips the install step.
#   --app ID             Steam app ID to install/launch. Without it the game steps are skipped.
#   --game-process RE    case-insensitive regex that matches the game's process in `ps` output
#                        (required with --app), e.g. 'orcs\.exe'.
#   --non-interactive    never wait for a person: login and game-install steps only verify state.
#   --report FILE        also write a Markdown report.
#
# Notes:
# - Process checks are global (`ps`), not per bottle. Close other Wine/Steam sessions first.
# - It stops every process in the bottle at the start and at the "quit" steps.
# - Process command lines can contain environment details, so they are counted, never printed.
# - Environment: TETHER (path to the tether binary), TETHER_HOME (as for the CLI).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TETHER="${TETHER:-$PWD/.build/debug/tether}"
BOTTLE="steam-checklist"
APP=""
GAME_RE=""
INTERACTIVE=1
REPORT=""
STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_EXE_WIN='C:\Program Files (x86)\Steam\Steam.exe'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bottle) BOTTLE="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --game-process) GAME_RE="$2"; shift 2 ;;
    --non-interactive) INTERACTIVE=0; shift ;;
    --report) REPORT="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done
if [[ -n "$APP" && -z "$GAME_RE" ]]; then echo "--app needs --game-process" >&2; exit 64; fi
if [[ -n "$APP" && ! "$APP" =~ ^[0-9]+$ ]]; then echo "--app must be a number" >&2; exit 64; fi

HOME_DIR="${TETHER_HOME:-$HOME/Library/Application Support/Tether}"
STEAM_DIR="$HOME_DIR/Bottles/$BOTTLE/prefix/drive_c/Program Files (x86)/Steam"

RESULTS=()
FAILS=0
record() { # status step detail
  printf '%-7s %-24s %s\n' "$1" "$2" "$3"
  RESULTS+=("$1|$2|$3")
  [[ "$1" == FAIL ]] && FAILS=$((FAILS + 1))
  return 0
}

count_procs() { ps -axo command | grep -ciE "$1" || true; }
steam_up()    { [[ "$(count_procs '[s]team\.exe')" -ge 1 ]]; }
renderer_up() { [[ "$(count_procs '[s]teamwebhelper\.exe.*--type=renderer')" -ge 1 ]]; }
game_up()     { [[ "$(count_procs "$GAME_RE")" -ge 1 ]]; }
all_down()    { [[ "$(count_procs '[s]team(webhelper)?\.exe')" -eq 0 && ( -z "$GAME_RE" || "$(count_procs "$GAME_RE")" -eq 0 ) ]]; }
wait_until()  { local secs=$1; shift; local waited=0; while (( waited < secs )); do "$@" && return 0; sleep 2; waited=$((waited + 2)); done; return 1; }
tether()      { "$TETHER" "$@"; }

pause_for_person() { # message
  (( INTERACTIVE )) || return 1
  printf '\n>>> %s\n>>> Press Enter when done (Ctrl-C to abort)... ' "$1" > /dev/tty
  read -r _ < /dev/tty
}

logged_in() { # at least one account recorded by Steam; the account itself is never printed
  [[ -f "$STEAM_DIR/config/loginusers.vdf" ]] && [[ "$(grep -c '"AccountName"' "$STEAM_DIR/config/loginusers.vdf")" -ge 1 ]]
}
game_installed() {
  tether steam list "$BOTTLE" 2>/dev/null | awk -F'\t' -v a="$APP" '$1==a && $3=="installed" {found=1} END{exit !found}'
}

# --- header -------------------------------------------------------------------------------------
echo "Tether Steam checklist"
echo "macOS:   $(sw_vers -productVersion) ($(uname -m))"
echo "commit:  $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "bottle:  $BOTTLE   app: ${APP:-none}"
echo

# --- 0. preconditions ---------------------------------------------------------------------------
if [[ ! -x "$TETHER" ]]; then swift build >/dev/null 2>&1 || true; fi
if [[ ! -x "$TETHER" ]]; then record FAIL "tether binary" "not found at $TETHER (run swift build)"; exit 1; fi

if tether runtime 2>/dev/null | grep -q 'wine'; then
  record PASS "runtime installed" "newest (used by bottles): $(tether runtime | tail -1 | cut -f1,2)"
else
  if tether runtime install >/dev/null 2>&1 && tether runtime | grep -q 'wine'; then
    record PASS "runtime installed" "installed now"
  else
    record FAIL "runtime installed" "tether runtime install failed"; exit 1
  fi
fi

tether bottle kill "$BOTTLE" >/dev/null 2>&1 || true
sleep 2
if all_down; then record PASS "clean start" "no Steam/game processes running"
else record FAIL "clean start" "other Steam/Wine processes are running; close them and retry"; exit 1; fi

# --- 1. bottle + install ------------------------------------------------------------------------
if tether bottle list 2>/dev/null | awk -F'\t' -v b="$BOTTLE" '$1==b {f=1} END{exit !f}'; then
  record SKIP "create bottle" "'$BOTTLE' already exists"
elif tether bottle create "$BOTTLE" >/dev/null 2>&1; then
  record PASS "create bottle" "$BOTTLE"
else
  record FAIL "create bottle" "tether bottle create failed"; exit 1
fi

if [[ -f "$STEAM_DIR/Steam.exe" ]]; then
  record SKIP "install Steam" "already installed in the bottle"
else
  tmp="$(mktemp -d)"
  if curl -fsSL --max-time 180 -o "$tmp/SteamSetup.exe" "$STEAM_INSTALLER_URL"; then
    sha="$(shasum -a 256 "$tmp/SteamSetup.exe" | cut -d' ' -f1)"
    if tether run --wait "$BOTTLE" "$tmp/SteamSetup.exe" /S >/dev/null 2>&1 && [[ -f "$STEAM_DIR/Steam.exe" ]]; then
      record PASS "install Steam" "SteamSetup.exe sha256=${sha:0:12}…"
    else
      record FAIL "install Steam" "installer ran but Steam.exe is missing"
    fi
  else
    record FAIL "install Steam" "could not download the installer"
  fi
  rm -rf "$tmp"
fi
[[ -f "$STEAM_DIR/Steam.exe" ]] || { record FAIL "abort" "no Steam, cannot continue"; exit 1; }

# --- 2. launch Steam, web helper ----------------------------------------------------------------
tether run "$BOTTLE" "$STEAM_EXE_WIN" >/dev/null 2>&1
if wait_until 300 steam_up && wait_until 120 renderer_up; then
  record PASS "Steam starts" "steam.exe and steamwebhelper renderer running"
else
  record FAIL "Steam starts" "no steam.exe or no steamwebhelper renderer within the timeout"
fi

# --- 3. login (person) --------------------------------------------------------------------------
if ! logged_in; then pause_for_person "Log in to Steam in the window (you type the credentials)." || true; fi
if logged_in; then record PASS "login" "an account is recorded by Steam"
else record FAIL "login" "no logged-in account found (re-run without --non-interactive to log in)"; fi

# --- 4. game install (person) -------------------------------------------------------------------
if [[ -z "$APP" ]]; then
  record SKIP "install game" "no --app given"
else
  if ! game_installed; then pause_for_person "Install app $APP in Steam and wait for the download to finish." || true; fi
  if game_installed; then record PASS "install game" "app $APP is listed as installed"
  else record FAIL "install game" "app $APP not installed (tether steam list)"; fi
fi

# --- 5. launch ----------------------------------------------------------------------------------
# On a failed launch, say what is still running and show Steam's own last log lines (with account
# ids masked), because a hung Steam leaves nothing else behind.
diagnose_launch() {
  echo "  diagnostics: steam.exe=$(count_procs '[s]team\.exe') webhelper=$(count_procs '[s]teamwebhelper') game=$(count_procs "$GAME_RE")"
  if [[ -f "$STEAM_DIR/logs/console_log.txt" ]]; then
    echo "  last Steam console_log lines (ids masked), and wine.log under Bottles/$BOTTLE/logs:"
    tail -n 6 "$STEAM_DIR/logs/console_log.txt" | sed -E 's/\[U:1:[0-9]+\]/[U:1:*]/g; s/7656119[0-9]{10}/<id>/g; s/^/    /' | cut -c1-170
  fi
}
launch_check() { # label
  tether steam launch --debug "$BOTTLE" "$APP" >/dev/null 2>&1
  if wait_until 180 game_up; then record PASS "$1" "game process is running"
  else record FAIL "$1" "game process did not appear within 180s (see diagnostics above and wine.log)"; diagnose_launch; fi
}
if [[ -n "$APP" ]]; then launch_check "launch game"; else record SKIP "launch game" "no --app given"; fi

# --- 6. quit ------------------------------------------------------------------------------------
quit_check() { # label
  tether bottle kill "$BOTTLE" >/dev/null 2>&1
  if wait_until 30 all_down; then record PASS "$1" "no Steam/game processes left"
  else record FAIL "$1" "processes still running after bottle kill"; fi
}
quit_check "quit"

# --- 7. relaunch (cold start) -------------------------------------------------------------------
if [[ -n "$APP" ]]; then
  launch_check "relaunch game"
  quit_check "final quit"
else
  record SKIP "relaunch game" "no --app given"
fi

# --- summary ------------------------------------------------------------------------------------
echo
passes=0; skips=0
for r in "${RESULTS[@]}"; do case "${r%%|*}" in PASS) passes=$((passes + 1));; SKIP) skips=$((skips + 1));; esac; done
echo "Result: $passes passed, $FAILS failed, $skips skipped"

if [[ -n "$REPORT" ]]; then
  {
    echo "# Steam checklist"
    echo
    echo "- macOS: $(sw_vers -productVersion) ($(uname -m))"
    echo "- Tether commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "- Runtime: $(tether runtime 2>/dev/null | tail -1 | cut -f1,2)"
    echo "- Bottle: $BOTTLE, app: ${APP:-none}"
    echo "- Date: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo
    echo "| Step | Result | Detail |"
    echo "|------|--------|--------|"
    for r in "${RESULTS[@]}"; do IFS='|' read -r s n d <<<"$r"; echo "| $n | $s | $d |"; done
  } > "$REPORT"
  echo "Report: $REPORT"
fi
exit $(( FAILS > 0 ))
