#!/system/bin/sh
# NVP Emulator for ICX1295 on non-Sony hardware
# Provides /dev/icx_nvp/ interface without kernel module

MODDIR=${0%/*}
NVP_DATA_DIR="$MODDIR/nvp_data"
NVP_DEV_DIR="/dev/icx_nvp"
LOG="$MODDIR/nvp_emulator.log"

# NVP Node definitions (from Sony firmware analysis)
# Format: NODE_NUMBER:DEFAULT_VALUE:DESCRIPTION
NVP_NODES="
000:00:version
001:00:boot_mode_flag
002:00:hold_mode
003:00:printk_flag
004:00:test_mode_flag
005:00:getty_mode_flag
006:00:quick_shutdown_flag
007:00:msc_only_mode_flag
008:00:application_debug_mode_flag
009:00:browser_log_mode_flag
010:00:btmw_log_mode_flag
011:00:checker_flag
012:00:nvram_init_flag
013:00:nvram_init_flag2
014:00:install_flag
015:00:disable_gva_boot_sound
016:00:europe_vol_regulation_flag
017:00:boot_image
018:00:model_id
019:00:serial_number
020:00:product_code
021:00:body_color
022:00:destination
023:00:user_destination
024:00:bundled_hp
025:00:emmc_capacity
026:00:sku_upid
027:00:product_id
028:00:service_id
029:00:usb_manufacture_name
030:00:usb_product_name
031:00:wifi_channel_index
032:00:boot_mode
033:00:bt_nvram_initflag
034:00:regiondata_version
035:00:user_install_flag
036-063:00:reserved1
064:00:volume_default
065:00:volume_default_se_high
066:00:volume_default_se_normal
067:00:volume_default_btl_high
068:00:volume_default_btl_normal
069:00:volume_gain_se
070:00:volume_gain_btl
071-081:00:reserved2
082:00:alc_voltbl_id_se_high
083:00:alc_voltbl_id_se_low
084:00:alc_voltbl_id_btl_high
085:00:alc_voltbl_id_btl_low
086:00:alc_voltbl_id_se_high_amb
087:00:alc_voltbl_id_se_high_nc
088:00:eq_voltbl_id_se_high
089:00:eq_voltbl_id_se_low
090:00:eq_voltbl_id_btl_high
091:00:eq_voltbl_id_btl_low
092:00:eq_voltbl_id_se_high_amb
093:00:eq_voltbl_id_se_high_nc
094-242:00:reserved3
"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

# Initialize NVP data directory
init_nvp_data() {
    mkdir -p "$NVP_DATA_DIR"
    log "Initializing NVP data directory: $NVP_DATA_DIR"

    # FIX B1 (verified live OP3 2026-07-16): NVP nodes must be 4-byte LITTLE-ENDIAN
    # binary. libizmproperties.so nvp_read expects 4 bytes (cmp w0,#4); Sony apps use
    # ByteBuffer LE getInt. Old text format caused BufferUnderflowException -> crash.
    if [ -x "$MODDIR/gen_nvp_binary.sh" ]; then
        sh "$MODDIR/gen_nvp_binary.sh" "$NVP_DATA_DIR"
    else
        log "WARNING: gen_nvp_binary.sh missing, falling back to zero-fill"
        i=0
        while [ $i -le 242 ]; do
            node=$(printf '%03d' $i)
            [ ! -f "$NVP_DATA_DIR/$node" ] && printf '\x00\x00\x00\x00' > "$NVP_DATA_DIR/$node"
            i=$((i + 1))
        done
    fi

    log "NVP data initialized"
}

# Create /dev/icx_nvp/ with symlinks to NVP data
create_nvp_devices() {
    log "Creating NVP device nodes"
    
    # Remove existing stubs if we have permission
    if [ -d "$NVP_DEV_DIR" ]; then
        rm -f "$NVP_DEV_DIR"/* 2>/dev/null || true
    else
        mkdir -p "$NVP_DEV_DIR"
    fi
    
    # Create symlinks to NVP data files
    i=0
    while [ $i -le 242 ]; do
        node=$(printf '%03d' $i)
        if [ -f "$NVP_DATA_DIR/$node" ]; then
#            ln -sf "$NVP_DATA_DIR/$node" "$NVP_DEV_DIR/$node" 2>/dev/null || true
            cp "$NVP_DATA_DIR/$node" "$NVP_DEV_DIR/$node" 2>/dev/null || true
        else
            touch "$NVP_DATA_DIR/$node"
#            ln -sf "$NVP_DATA_DIR/$node" "$NVP_DEV_DIR/$node" 2>/dev/null || true
            cp "$NVP_DATA_DIR/$node" "$NVP_DEV_DIR/$node" 2>/dev/null || true
        fi
        i=$((i + 1))
    done
    
    # Try to set permissions if we have permission
    chmod 0777 "$NVP_DEV_DIR"/* 2>/dev/null || true
    chmod 0777 "$NVP_DEV_DIR" 2>/dev/null || true
    
    log "Created $(ls -1 "$NVP_DEV_DIR" 2>/dev/null | wc -l) NVP device nodes"
}

# Read NVP node value
nvp_read() {
    local input="$1"
    # Remove leading zeros for printf
    local num=$(echo "$input" | sed 's/^0*//' || echo "0")
    [ -z "$num" ] && num=0
    local node=$(printf '%03d' $num)
    local file="$NVP_DATA_DIR/$node"
    
    if [ -f "$file" ]; then
        cat "$file"
    else
        echo "00"
    fi
}

# Write NVP node value
nvp_write() {
    local input="$1"
    local value="$2"
    # Remove leading zeros for printf
    local num=$(echo "$input" | sed 's/^0*//' || echo "0")
    [ -z "$num" ] && num=0
    local node=$(printf '%03d' $num)
    local file="$NVP_DATA_DIR/$node"
    
    echo -n "$value" > "$file"
    log "NVP write: node=$node value=$value"
}

# Show NVP statistics
nvp_stat() {
    echo "NVP Emulator Status"
    echo "==================="
    echo "Data directory: $NVP_DATA_DIR"
    echo "Device directory: $NVP_DEV_DIR"
    echo "Total nodes: $(ls -1 "$NVP_DATA_DIR" | wc -l)"
    echo ""
    echo "Node values:"
    i=0
    while [ $i -le 242 ]; do
        node=$(printf '%03d' $i)
        value=$(nvp_read $i)
        if [ "$value" != "00" ] && [ -n "$value" ]; then
            echo "  $node: $value"
        fi
        i=$((i + 1))
    done
}

# Erase all NVP data
nvp_eraseall() {
    log "Erasing all NVP data"
    i=0
    while [ $i -le 242 ]; do
        node=$(printf '%03d' $i)
        echo -n "FF" > "$NVP_DATA_DIR/$node"
        i=$((i + 1))
    done
    log "NVP erase complete"
}

# Main
case "$1" in
    init)
        init_nvp_data
        create_nvp_devices
        ;;
    read)
        nvp_read "$2"
        ;;
    write)
        nvp_write "$2" "$3"
        ;;
    stat)
        nvp_stat
        ;;
    eraseall)
        nvp_eraseall
        ;;
    *)
        echo "Usage: $0 {init|read|write|stat|eraseall}"
        echo "  init     - Initialize NVP data and devices"
        echo "  read N   - Read node N value"
        echo "  write N V - Write value V to node N"
        echo "  stat     - Show NVP statistics"
        echo "  eraseall - Erase all NVP data"
        ;;
esac
