#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_CONFIG="${SCRIPT_DIR}/watcher.conf"
DEFAULT_WATCH_DIR="${SCRIPT_DIR}/watched"
DEFAULT_FIFO="${SCRIPT_DIR}/watcher.fifo"
DEFAULT_LOG="${SCRIPT_DIR}/logs/watcher.log"
DEFAULT_PID="${SCRIPT_DIR}/watcher.pid"
DEFAULT_INTERVAL=5
DEFAULT_LOG_LEVEL="INFO"


usage() {
    cat >&2 << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --config FILE       Config file           (default: $DEFAULT_CONFIG)
  -w, --watch-dir DIR     Directory to watch    (default: $DEFAULT_WATCH_DIR)
  -f, --fifo PATH         FIFO path             (default: $DEFAULT_FIFO)
  -l, --log FILE          Log file              (default: $DEFAULT_LOG)
  -p, --pid FILE          PID file              (default: $DEFAULT_PID)
  -i, --interval SEC      Poll interval seconds (default: $DEFAULT_INTERVAL)
  -L, --log-level LEVEL   DEBUG|INFO|WARN|ERROR (default: $DEFAULT_LOG_LEVEL)
  -h, --help              Show this help

Priority: CLI args > config file > built-in defaults
EOF
    exit 1
}


CLI_CONFIG=""
CLI_WATCH_DIR=""
CLI_FIFO=""
CLI_LOG=""
CLI_PID=""
CLI_INTERVAL=""
CLI_LOG_LEVEL=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)      CLI_CONFIG="$2";    shift 2 ;;
            -w|--watch-dir)   CLI_WATCH_DIR="$2"; shift 2 ;;
            -f|--fifo)        CLI_FIFO="$2";      shift 2 ;;
            -l|--log)         CLI_LOG="$2";        shift 2 ;;
            -p|--pid)         CLI_PID="$2";        shift 2 ;;
            -i|--interval)    CLI_INTERVAL="$2";  shift 2 ;;
            -L|--log-level)   CLI_LOG_LEVEL="$2"; shift 2 ;;
            -h|--help)        usage ;;
            *) echo "Unknown option: $1" >&2; usage ;;
        esac
    done
}


apply_config() {
    local config_file="${CLI_CONFIG:-$DEFAULT_CONFIG}"

    WATCH_DIR="$DEFAULT_WATCH_DIR"
    FIFO_PATH="$DEFAULT_FIFO"
    LOG_FILE="$DEFAULT_LOG"
    PID_FILE="$DEFAULT_PID"
    POLL_INTERVAL="$DEFAULT_INTERVAL"
    LOG_LEVEL="$DEFAULT_LOG_LEVEL"

    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
    CONFIG_FILE="$config_file"

    [[ -n "$CLI_WATCH_DIR"  ]] && WATCH_DIR="$CLI_WATCH_DIR"
    [[ -n "$CLI_FIFO"       ]] && FIFO_PATH="$CLI_FIFO"
    [[ -n "$CLI_LOG"        ]] && LOG_FILE="$CLI_LOG"
    [[ -n "$CLI_PID"        ]] && PID_FILE="$CLI_PID"
    [[ -n "$CLI_INTERVAL"   ]] && POLL_INTERVAL="$CLI_INTERVAL"
    [[ -n "$CLI_LOG_LEVEL"  ]] && LOG_LEVEL="$CLI_LOG_LEVEL"
}

EVENTS_TOTAL=0
EVENTS_SESSION=0
START_TIME=$(date +%s)
MODE="normal"

FLAG_TERM=0
FLAG_HUP=0
FLAG_USR1=0
FLAG_USR2=0

log() {
    local level="$1"; shift
    local message="$*"
    case "$LOG_LEVEL" in
        ERROR) [[ "$level" == "ERROR" ]] || return 0 ;;
        WARN)  [[ "$level" =~ ^(WARN|ERROR)$ ]] || return 0 ;;
        INFO)  [[ "$level" =~ ^(INFO|WARN|ERROR)$ ]] || return 0 ;;
    esac
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $message" >> "$LOG_FILE"
}

log_info()  { log INFO  "$@"; }
log_debug() { log DEBUG "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }


handle_term() { FLAG_TERM=1; }
handle_hup()  { FLAG_HUP=1;  }
handle_usr1() { FLAG_USR1=1; }
handle_usr2() { FLAG_USR2=1; }

trap 'handle_term' TERM INT
trap 'handle_hup'  HUP
trap 'handle_usr1' USR1
trap 'handle_usr2' USR2

do_shutdown() {
    log_info "SIGTERM/SIGINT received — graceful shutdown initiated"
    log_info "Session stats: events_processed=${EVENTS_SESSION}, total_events=${EVENTS_TOTAL}"
    log_info "Watcher stopped (PID=$$)"
    rm -f "$PID_FILE"
    rm -f "$FIFO_PATH" 2>/dev/null || true
    exit 0
}

do_reload() {
    log_info "SIGHUP received — reloading configuration"
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        [[ -n "$CLI_WATCH_DIR"  ]] && WATCH_DIR="$CLI_WATCH_DIR"
        [[ -n "$CLI_FIFO"       ]] && FIFO_PATH="$CLI_FIFO"
        [[ -n "$CLI_LOG"        ]] && LOG_FILE="$CLI_LOG"
        [[ -n "$CLI_INTERVAL"   ]] && POLL_INTERVAL="$CLI_INTERVAL"
        [[ -n "$CLI_LOG_LEVEL"  ]] && LOG_LEVEL="$CLI_LOG_LEVEL"
        log_info "Configuration reloaded from $CONFIG_FILE"
        log_info "  WATCH_DIR=$WATCH_DIR  POLL_INTERVAL=$POLL_INTERVAL  LOG_LEVEL=$LOG_LEVEL"
    else
        log_warn "Config file not found: $CONFIG_FILE — keeping current settings"
    fi
}

do_status_snapshot() {
    local uptime=$(( $(date +%s) - START_TIME ))
    local hh=$(( uptime / 3600 ))
    local mm=$(( (uptime % 3600) / 60 ))
    local ss=$(( uptime % 60 ))
    log_info "=== STATUS SNAPSHOT ============="
    log_info "  PID              : $$"
    log_info "  Uptime           : ${hh}h ${mm}m ${ss}s"
    log_info "  Mode             : $MODE"
    log_info "  Log level        : $LOG_LEVEL"
    log_info "  Watch dir        : $WATCH_DIR"
    log_info "  FIFO             : $FIFO_PATH"
    log_info "  Config file      : $CONFIG_FILE"
    log_info "  Events (session) : $EVENTS_SESSION"
    log_info "  Events (total)   : $EVENTS_TOTAL"
    log_info "================================="
}

do_log_rotate() {
    log_info "SIGUSR2 received — rotating log / toggling mode"
    local ts; ts=$(date '+%Y%m%d_%H%M%S')
    local archive_log="${SCRIPT_DIR}/archive/watcher_${ts}.log"
    if [[ -f "$LOG_FILE" ]]; then
        cp "$LOG_FILE" "$archive_log"
        : > "$LOG_FILE"
        log_info "Log rotated — archived to $archive_log"
    fi
    if [[ "$MODE" == "normal" ]]; then
        MODE="verbose"; LOG_LEVEL="DEBUG"
    else
        MODE="normal"; LOG_LEVEL="INFO"
    fi
    log_info "Mode switched to: $MODE (LOG_LEVEL=$LOG_LEVEL)"
}

start_fifo_reader() {
    rm -f "$FIFO_PATH"
    mkfifo "$FIFO_PATH"
    log_info "FIFO created at $FIFO_PATH"
    exec 3<>"$FIFO_PATH"
    (
        while true; do
            if IFS= read -r -t 1 msg <&3 2>/dev/null; then
                [[ -z "$msg" ]] && continue
                local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
                echo "[$ts] [FIFO] Received: $msg" >> "$LOG_FILE"
                case "$msg" in
                    STATUS)
                        echo "[$ts] [FIFO] -> triggering status snapshot" >> "$LOG_FILE"
                        kill -USR1 $$ 2>/dev/null || true ;;
                    STOP)
                        echo "[$ts] [FIFO] -> triggering graceful stop" >> "$LOG_FILE"
                        kill -TERM $$ 2>/dev/null || true ;;
                    MODE_CHANGE)
                        echo "[$ts] [FIFO] -> triggering mode change" >> "$LOG_FILE"
                        kill -USR2 $$ 2>/dev/null || true ;;
                    RELOAD)
                        echo "[$ts] [FIFO] -> triggering config reload" >> "$LOG_FILE"
                        kill -HUP $$ 2>/dev/null || true ;;
                    *)
                        echo "[$ts] [FIFO] Unknown command ignored: $msg" >> "$LOG_FILE" ;;
                esac
            fi
        done
    ) &
    log_debug "FIFO reader PID=$!"
}


declare -A KNOWN_FILES=()

init_known_files() {
    KNOWN_FILES=()
    if [[ -d "$WATCH_DIR" ]]; then
        while IFS= read -r -d '' f; do
            KNOWN_FILES["$f"]=1
        done < <(find "$WATCH_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
    fi
    log_debug "Initialized: ${#KNOWN_FILES[@]} known file(s)"
}

check_watch_dir() {
    [[ -d "$WATCH_DIR" ]] || { log_warn "Watch directory missing: $WATCH_DIR"; return; }
    declare -A current_files=()
    while IFS= read -r -d '' f; do
        current_files["$f"]=1
    done < <(find "$WATCH_DIR" -maxdepth 1 -type f -print0 2>/dev/null)

    for f in "${!current_files[@]}"; do
        if [[ -z "${KNOWN_FILES[$f]+_}" ]]; then
            KNOWN_FILES["$f"]=1
            (( EVENTS_TOTAL++ ))
            (( EVENTS_SESSION++ ))
            log_info "EVENT new_file path=$f size=$(stat -c%s "$f" 2>/dev/null || echo '?')"
        fi
    done

    for f in "${!KNOWN_FILES[@]}"; do
        if [[ -z "${current_files[$f]+_}" ]]; then
            unset 'KNOWN_FILES[$f]'
            (( EVENTS_TOTAL++ ))
            (( EVENTS_SESSION++ ))
            log_info "EVENT removed_file path=$f"
        fi
    done
}

startup() {
    mkdir -p "$(dirname "$LOG_FILE")" "${SCRIPT_DIR}/archive" "${SCRIPT_DIR}/reports" "$WATCH_DIR"
    log_info "========================================="
    log_info "Watcher starting (PID=$$)"
    log_info "  Watch dir      : $WATCH_DIR"
    log_info "  FIFO           : $FIFO_PATH"
    log_info "  Poll interval  : ${POLL_INTERVAL}s"
    log_info "  Log level      : $LOG_LEVEL"
    log_info "  Config file    : $CONFIG_FILE"
    log_info "========================================="
    echo $$ > "$PID_FILE"
    init_known_files
    start_fifo_reader
}

main() {
    parse_args "$@"
    apply_config
    startup
    while true; do
        if (( FLAG_TERM )); then FLAG_TERM=0; do_shutdown;         fi
        if (( FLAG_HUP  )); then FLAG_HUP=0;  do_reload;           fi
        if (( FLAG_USR1 )); then FLAG_USR1=0; do_status_snapshot;  fi
        if (( FLAG_USR2 )); then FLAG_USR2=0; do_log_rotate;       fi
        check_watch_dir
        sleep "$POLL_INTERVAL"
    done
}

main "$@"
