#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="${SCRIPT_DIR}/archive"
REPORTS_DIR="${SCRIPT_DIR}/reports"
KEEP_DAYS=30
LOG_FILE="${SCRIPT_DIR}/logs/watcher.log"

removed=0
freed=0

cleanup_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return

    while IFS= read -r -d '' f; do
        local size
        size=$(stat -c%s "$f" 2>/dev/null || echo 0)
        rm -f "$f"
        (( removed++ )) || true
        (( freed += size )) || true
    done < <(find "$dir" -maxdepth 1 -type f -mtime "+${KEEP_DAYS}" -print0 2>/dev/null)
}

cleanup_dir "$ARCHIVE_DIR"
cleanup_dir "$REPORTS_DIR"

ts=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$ts] [INFO] Cleanup: removed=$removed files older than ${KEEP_DAYS}d, freed=${freed} bytes" >> "$LOG_FILE"
echo "Cleanup done: $removed files removed (${freed} bytes freed)."
