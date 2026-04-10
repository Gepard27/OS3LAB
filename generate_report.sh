#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/watcher.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/logs/watcher.log}"
REPORTS_DIR="${SCRIPT_DIR}/reports"
DATETIME=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="${REPORTS_DIR}/report_${DATETIME}.txt"
mkdir -p "$REPORTS_DIR"

count_matches() {
    local pattern="$1" file="$2"
    [[ ! -f "$file" ]] && echo 0 && return
    grep "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' '
}

total_lines=0; [[ -f "$LOG_FILE" ]] && total_lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
events_new=$(  count_matches "EVENT new_file"     "$LOG_FILE")
events_del=$(  count_matches "EVENT removed_file" "$LOG_FILE")
events_fifo=$( count_matches "\[FIFO\]"           "$LOG_FILE")
sig_hup=$(     count_matches "SIGHUP received"    "$LOG_FILE")
sig_usr1=$(    count_matches "SIGUSR1"            "$LOG_FILE")
sig_usr2=$(    count_matches "SIGUSR2"            "$LOG_FILE")
errors=$(      count_matches "\[ERROR\]"          "$LOG_FILE")
warnings=$(    count_matches "\[WARN\]"           "$LOG_FILE")
starts=$(      count_matches "Watcher starting"  "$LOG_FILE")
stops=$(       count_matches "Watcher stopped"   "$LOG_FILE")
events_total=$(( events_new + events_del ))

last_events="(no events yet)"
[[ -f "$LOG_FILE" ]] && tmp=$(grep "EVENT" "$LOG_FILE" 2>/dev/null | tail -n 10) && [[ -n "$tmp" ]] && last_events="$tmp"

generated_at=$(date '+%Y-%m-%d %H:%M:%S')

{
echo "============================================================="
echo "  WATCHER SERVICE REPORT"
echo "  Generated : $generated_at"
echo "  Report    : $REPORT_FILE"
echo "============================================================="
echo ""
echo "LOG FILE SUMMARY"
echo "  File            : $LOG_FILE"
echo "  Total lines     : $total_lines"
echo ""
echo "SERVICE LIFECYCLE"
echo "  Starts          : $starts"
echo "  Stops           : $stops"
echo ""
echo "EVENTS"
echo "  New files       : $events_new"
echo "  Removed files   : $events_del"
echo "  Total events    : $events_total"
echo "  FIFO messages   : $events_fifo"
echo ""
echo "SIGNALS RECEIVED"
echo "  SIGHUP (reload) : $sig_hup"
echo "  SIGUSR1 (status): $sig_usr1"
echo "  SIGUSR2 (rotate): $sig_usr2"
echo ""
echo "ISSUES"
echo "  Errors          : $errors"
echo "  Warnings        : $warnings"
echo ""
echo "LAST 10 EVENTS"
echo "$last_events"
echo ""
echo "============================================================="
} > "$REPORT_FILE"

echo "Report saved: $REPORT_FILE"
