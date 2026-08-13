#!/system/bin/sh
# Integration script for NVP Emulator with existing Magisk module
# This script shows how to integrate the NVP emulator into service.sh

MODDIR=${0%/*}
NVP_EMU_DIR="$MODDIR/nvp_emulator"

# Add this to the beginning of service.sh, after the property setup section

cat << 'EOF'
# ============================================================
# NVP EMULATOR SETUP
# ============================================================
NVP_EMU_DIR="$MODDIR/nvp_emulator"
NVP_DATA_DIR="$NVP_EMU_DIR/nvp_data"

# Initialize NVP emulator
if [ -d "$NVP_EMU_DIR" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') service: initializing NVP emulator" >> "$LOG"
    
    # Create NVP data directory
    mkdir -p "$NVP_DATA_DIR"
    
    # Initialize default NVP nodes
    i=0
    while [ $i -le 242 ]; do
        node=$(printf '%03d' $i)
        [ ! -f "$NVP_DATA_DIR/$node" ] && echo -n "00" > "$NVP_DATA_DIR/$node"
        i=$((i + 1))
    done
    
    # Create /dev/icx_nvp/ with symlinks
    rm -rf /dev/icx_nvp
    mkdir -p /dev/icx_nvp
    
    i=0
    while [ $i -le 242 ]; do
        node=$(printf '%03d' $i)
#        ln -sf "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node"
        cp "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node"
        i=$((i + 1))
    done
    
    chmod 0777 /dev/icx_nvp/*
    chmod 0777 /dev/icx_nvp
    
    # Create wrapper scripts for Sony NVP tools
    mkdir -p "$MODDIR/system/vendor/bin"
    for tool in nvpflag nvpnode nvpinfo nvpstr nvp; do
        cat > "$MODDIR/system/vendor/bin/$tool" << WRAPPER
#!/system/bin/sh
exec $NVP_EMU_DIR/nvp_wrapper.sh "\$@"
WRAPPER
        chmod 0755 "$MODDIR/system/vendor/bin/$tool"
    done
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') service: NVP emulator initialized" >> "$LOG"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') service: NVP emulator directory not found" >> "$LOG"
fi
EOF
