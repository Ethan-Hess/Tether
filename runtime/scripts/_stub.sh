# Shared helper for not-yet-implemented runtime build scripts.
stub() {
  echo "$(basename "$0"): not implemented yet." >&2
  echo "Intended steps:" >&2
  sed -n 's/^# STEP: /  - /p' "$0" >&2
  exit 2
}
