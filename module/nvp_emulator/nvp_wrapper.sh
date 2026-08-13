#!/system/bin/sh
# NVP Tool Wrapper for ICX1295 on non-Sony hardware
# Intercepts Sony NVP tools and redirects to emulator

MODDIR=${0%/*}
NVP_DATA_DIR="$MODDIR/nvp_data"
NVP_EMULATOR="$MODDIR/nvp_emulator.sh"

# Get the tool name from the command
TOOL=$(basename "$0")

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$TOOL] $1" >> "$MODDIR/wrapper.log"
}

# Convert zone name to node number
zone_to_node() {
    case "$1" in
        bmd) echo "001" ;;  # boot mode flag
        prk) echo "003" ;;  # printk flag
        tst) echo "004" ;;  # test mode flag
        gty) echo "005" ;;  # getty mode flag
        mso) echo "007" ;;  # MSC only mode flag
        nvr) echo "012" ;;  # NVRAM init flag
        ins) echo "014" ;;  # install flag
        *)   echo "$1" ;;   # assume it's a node number
    esac
}

# nvpflag wrapper
nvpflag_wrapper() {
    local hex_mode=0
    local zone=""
    local write_data=""
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -x) hex_mode=1; shift ;;
            *)  if [ -z "$zone" ]; then
                    zone="$1"
                else
                    write_data="$1"
                fi
                shift ;;
        esac
    done
    
    [ -z "$zone" ] && echo "usage: nvpflag [-x] ZONE [WRITE_DATA]" && exit 1
    
    local node=$(zone_to_node "$zone")
    
    if [ -n "$write_data" ]; then
        # Write mode
        $NVP_EMULATOR write "$node" "$write_data"
        log "Write zone=$zone node=$node data=$write_data"
    else
        # Read mode
        local value=$($NVP_EMULATOR read "$node")
        if [ $hex_mode -eq 1 ]; then
            echo "0x$value"
        else
            echo "$value"
        fi
        log "Read zone=$zone node=$node value=$value"
    fi
}

# nvpnode wrapper
nvpnode_wrapper() {
    $NVP_EMULATOR stat
}

# nvpinfo wrapper
nvpinfo_wrapper() {
    echo "NVP Info (Emulated)"
    echo "=================="
    echo "Driver version: 0x00000001"
    echo "Head sector: 0"
    echo "Sector count: 243"
    echo ""
    $NVP_EMULATOR stat
}

# nvp wrapper
nvp_wrapper() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        stat)
            local target="$1"
            case "$target" in
                node|zone|table|shadow|bmp)
                    $NVP_EMULATOR stat
                    ;;
                *)
                    echo "usage: nvp stat node|zone|table|shadow|bmp"
                    ;;
            esac
            ;;
        eraseall)
            $NVP_EMULATOR eraseall
            ;;
        zw|zrf|zrw|wf)
            echo "Write operation - emulated"
            # For now, just read the data
            local zone="$1"
            local size="$2"
            shift 2
            log "Write zone=$zone size=$size data=$@"
            ;;
        *)
            echo "usage: nvp stat node|zone|table|shadow|bmp"
            echo "       nvp eraseall"
            ;;
    esac
}

# nvpstr wrapper
nvpstr_wrapper() {
    local node="$1"
    shift
    
    if [ $# -gt 0 ]; then
        # Write mode
        $NVP_EMULATOR write "$node" "$*"
        log "Write node=$node data=$*"
    else
        # Read mode
        $NVP_EMULATOR read "$node"
    fi
}

# Main dispatch
case "$TOOL" in
    nvpflag)
        nvpflag_wrapper "$@"
        ;;
    nvpnode)
        nvpnode_wrapper "$@"
        ;;
    nvpinfo)
        nvpinfo_wrapper "$@"
        ;;
    nvpstr)
        nvpstr_wrapper "$@"
        ;;
    nvp)
        nvp_wrapper "$@"
        ;;
    *)
        echo "Unknown NVP tool: $TOOL"
        exit 1
        ;;
esac
