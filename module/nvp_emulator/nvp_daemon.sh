#!/system/bin/sh
# NVP Daemon - Persistent NVP emulator service
# Runs as a daemon and handles NVP requests

MODDIR=${0%/*}
NVP_DATA_DIR="$MODDIR/nvp_data"
NVP_SOCKET="/dev/socket/nvp_emulator"
NVP_PID_FILE="$MODDIR/nvp_daemon.pid"
NVP_LOG="$MODDIR/nvp_daemon.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$NVP_LOG"
}

# Start daemon
start_daemon() {
    if [ -f "$NVP_PID_FILE" ]; then
        local pid=$(cat "$NVP_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Daemon already running (PID=$pid)"
            return 0
        fi
    fi
    
    log "Starting NVP daemon..."
    
    # Create socket directory
    mkdir -p /dev/socket
    
    # Start daemon in background
    (
        # Initialize NVP data (4-byte LE binary, FIX B1)
        mkdir -p "$NVP_DATA_DIR"
        if [ -x "$MODDIR/gen_nvp_binary.sh" ]; then
            sh "$MODDIR/gen_nvp_binary.sh" "$NVP_DATA_DIR"
        else
            i=0
            while [ $i -le 242 ]; do
                node=$(printf '%03d' $i)
                [ ! -f "$NVP_DATA_DIR/$node" ] && printf '\x00\x00\x00\x00' > "$NVP_DATA_DIR/$node"
                i=$((i + 1))
            done
        fi
        
        # Create /dev/icx_nvp
        rm -rf /dev/icx_nvp
        mkdir -p /dev/icx_nvp
        i=0
        while [ $i -le 242 ]; do
            node=$(printf '%03d' $i)
#            ln -sf "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node"
            cp "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node"
            i=$((i + 1))
        done
        chmod 0777 /dev/icx_nvp/*
        chmod 0777 /dev/icx_nvp
        
        log "NVP daemon initialized"
        
        # Keep running
        while true; do
            sleep 3600
        done
    ) &
    
    local pid=$!
    echo "$pid" > "$NVP_PID_FILE"
    log "NVP daemon started (PID=$pid)"
    return 0
}

# Stop daemon
stop_daemon() {
    if [ -f "$NVP_PID_FILE" ]; then
        local pid=$(cat "$NVP_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$NVP_PID_FILE"
            log "NVP daemon stopped"
        fi
    fi
}

# Status
status_daemon() {
    if [ -f "$NVP_PID_FILE" ]; then
        local pid=$(cat "$NVP_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "NVP daemon running (PID=$pid)"
            return 0
        fi
    fi
    echo "NVP daemon not running"
    return 1
}

# Main
case "$1" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    status)
        status_daemon
        ;;
    restart)
        stop_daemon
        sleep 1
        start_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        ;;
esac
