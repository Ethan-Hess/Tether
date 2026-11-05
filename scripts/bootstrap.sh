#!/usr/bin/env bash
# Checks that this Mac can build Tether (host) and, optionally, the runtime.
set -uo pipefail

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
FAILED=0

echo "Host:"
[[ "$(uname -m)" == "arm64" ]] && ok "Apple Silicon" || bad "Apple Silicon required"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) && ok "macOS $(sw_vers -productVersion)" || bad "macOS 14+ required"
if command -v swift >/dev/null; then ok "$(swift --version 2>&1 | head -1)"; else bad "Swift not found: install Xcode or run xcode-select --install"; fi
if [[ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime || -e /Library/Apple/usr/share/rosetta/rosetta ]]; then
  ok "Rosetta 2"
else
  bad "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
fi

echo "Runtime build (optional):"
for tool in brew git meson ninja bison flex x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
  command -v "$tool" >/dev/null && ok "$tool" || warn "$tool not found (needed only to build the runtime; see runtime/README.md)"
done

exit $FAILED
