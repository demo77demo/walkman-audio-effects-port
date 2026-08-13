#!/system/bin/sh
# NVP FUSE Emulator - Advanced char device emulation
# Uses FUSE to provide proper /dev/icx_nvp/ interface

MODDIR=${0%/*}
NVP_DATA_DIR="$MODDIR/nvp_data"
NVP_MOUNT_DIR="/dev/icx_nvp"
NVP_LOG="$MODDIR/nvp_fuse.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$NVP_LOG"
}

# Check if FUSE is available
check_fuse() {
    if [ -e /dev/fuse ]; then
        log "FUSE available"
        return 0
    else
        log "FUSE not available"
        return 1
    fi
}

# Mount FUSE filesystem for NVP
mount_nvp_fuse() {
    if ! check_fuse; then
        log "FUSE not available, using file stubs"
        return 1
    fi
    
    # Unmount if already mounted
    umount "$NVP_MOUNT_DIR" 2>/dev/null
    
    # Create mount point
    mkdir -p "$NVP_MOUNT_DIR"
    
    # Mount FUSE with nvp_helper
    "$MODDIR/nvp_fuse_helper" "$NVP_MOUNT_DIR" "$NVP_DATA_DIR" &
    FUSE_PID=$!
    
    log "FUSE mounted at $NVP_MOUNT_DIR (PID=$FUSE_PID)"
    return 0
}

# Unmount NVP FUSE
unmount_nvp_fuse() {
    if mountpoint -q "$NVP_MOUNT_DIR"; then
        fusermount -u "$NVP_MOUNT_DIR" 2>/dev/null || umount "$NVP_MOUNT_DIR"
        log "FUSE unmounted"
    fi
}

# Main
case "$1" in
    mount)
        mount_nvp_fuse
        ;;
    unmount)
        unmount_nvp_fuse
        ;;
    status)
        if mountpoint -q "$NVP_MOUNT_DIR" 2>/dev/null; then
            echo "NVP FUSE mounted at $NVP_MOUNT_DIR"
        else
            echo "NVP FUSE not mounted"
        fi
        ;;
    *)
        echo "Usage: $0 {mount|unmount|status}"
        ;;
esac
