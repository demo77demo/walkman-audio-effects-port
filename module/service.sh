#!/system/bin/sh
# service.sh for ICX1295 Audio HAL Magisk Module
# Main service initialization script
# Runs in late_start service mode (non-blocking)

MODDIR=${0%/*}
MODPATH=$MODDIR

# ============================================================
# LOG ROTATION — prevent debug.log from growing unbounded
# ============================================================
LOG="$MODDIR/debug.log"
MAX_LOG_SIZE=524288  # 512KB
if [ -f "$LOG" ]; then
    LOG_SIZE=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG" "${LOG}.old" 2>/dev/null
    fi
fi

# Logging (set -x traces all commands)
exec 2>$LOG
set -x

# ============================================================
# DEVICE DETECTION
# ============================================================
MANUFACTURER=$(getprop ro.product.manufacturer | tr -d '[:space:]')
HARDWARE=$(getprop ro.hardware | tr -d '[:space:]')
#IS_SONY=$( [ "$MANUFACTURER" = "OnePlus" ] && echo "true" || echo "false" )

API=$(getprop ro.build.version.sdk)
[ ! -d $MODDIR/vendor ] || [ -L $MODDIR/vendor ] && MODSYSTEM=/system
MOD=/data/adb/modules/nomount
NM=$MOD/bin/nm
NOMOUNT=false
[ ! -f $MOD/disable ] && [ -x $NM ] && $NM v >/dev/null 2>&1 && NOMOUNT=true

# NoMount
if $NOMOUNT; then
  DES=/system/etc/vintf/manifest.xml
  FILE=$MODPATH$DES
  if [ -f $FILE ] && [ -f $DES ]; then
    $NM del $DES 2>/dev/null || true
    $NM add $DES $FILE
  fi
fi

# ============================================================
# PROPERTY SETUP — ICX1295 CEW Region
# ============================================================

# Core audio
resetprop -n ro.sony.volume_limit 0
resetprop -n ro.sony.walkman.euvollimit 0
resetprop -p --delete persist.vendor.audio.mixerthread.res
#resetprop -n persist.vendor.audio.mixerthread.res true
resetprop -n persist.vendor.audio.mixerthread.res std
resetprop -n ro.sony.deviceimplementationid 0x310000

# Device identity
resetprop -n ro.product.destination 0x3
resetprop -n ro.user.destination 0x3
resetprop -n ro.product.model_id 0x310000
resetprop -n ro.product.body_color 0
resetprop -n ro.product.bundled_hp 0
resetprop -n ro.product.serial_number 00000000
resetprop -n ro.product.product_code 00000000
resetprop -n ro.product.usb_manufacture_name Sony
resetprop -n ro.product.usb_product_name WALKMAN
resetprop -n ro.regiondata.version 1
resetprop -n ro.user.install.flag 1

# Vendor identity
resetprop -n vendor.destination 259
resetprop -n vendor.model_id 0x310000
resetprop -n vendor.body_color 0
resetprop -n vendor.serial_number 00000000
resetprop -n vendor.emmc_capacity 32
resetprop -n vendor.sku.upid 0x310000
resetprop -n vendor.product_id 0x310000
resetprop -n vendor.service_id 512
resetprop -n vendor.safe_volume.enabled 1

# Audio effects (all enabled for CEW)
resetprop -n ro.effect.dsee_ai.enabled true
resetprop -n ro.effect.clear_phase.enabled true
resetprop -n ro.effect.vinyl_processor.enabled true
resetprop -n ro.effect.source_direct.enabled true
resetprop -n ro.effect.clear_audio_plus.enabled true
resetprop -n ro.effect.dc_phase_linearizer.enabled true
resetprop -n ro.effect.dynamic_normalizer.enabled true
resetprop -n ro.effect.equalizer_10.enabled true
resetprop -n ro.effect.dc_phase_linearizer.type 0
resetprop -n ro.effect.equalizer_10.preset 0
resetprop -n ro.effect.vinyl_processor.type 0
resetprop -n ro.dynamic_normalizer.mode 0

# Effect file paths
resetprop -n ro.dsee_ai.filepath.bin /vendor/etc/DseeAi_ICX1295.bin
resetprop -n ro.dsee_ai.filepath.dcfg /vendor/etc/DseeAi_ICX1295.dcfg
resetprop -n ro.clear_phase.filepath.lps_44100 /vendor/etc/ClearPhase_HP_NW510N_44100.lps
resetprop -n ro.clear_phase.filepath.lps_48000 /vendor/etc/ClearPhase_HP_NW510N_48000.lps
resetprop -n ro.clear_phase.filepath.lps_88200 /vendor/etc/ClearPhase_HP_NW510N_88200.lps
resetprop -n ro.clear_phase.filepath.lps_96000 /vendor/etc/ClearPhase_HP_NW510N_96000.lps
resetprop -n ro.clear_phase.filepath.lps_176400 /vendor/etc/ClearPhase_HP_NW510N_176400.lps
resetprop -n ro.clear_phase.filepath.lps_192000 /vendor/etc/ClearPhase_HP_NW510N_192000.lps
resetprop -n ro.vinylprocessor.filepath.vinylcoeff /vendor/etc/vinylcoeff.csv

# Volume defaults (0x70 = default step)
resetprop -n ro.volume.default 0x70
resetprop -n ro.volume.default.se.high 0x70
resetprop -n ro.volume.default.se.normal 0x70
resetprop -n ro.volume.default.btl.high 0x70
resetprop -n ro.volume.default.btl.normal 0x70
resetprop -n ro.volume.gain.se 0
resetprop -n ro.volume.gain.btl 0

# ALC/EQ table IDs
resetprop -n ro.alc.voltbl_id.se_high 0
resetprop -n ro.alc.voltbl_id.se_low 0
resetprop -n ro.alc.voltbl_id.btl_high 0
resetprop -n ro.alc.voltbl_id.btl_low 0
resetprop -n ro.alc.voltbl_id.se_high_amb 0
resetprop -n ro.alc.voltbl_id.se_high_nc 0
resetprop -n ro.eq.voltbl_id.se_high 0
resetprop -n ro.eq.voltbl_id.se_low 0
resetprop -n ro.eq.voltbl_id.btl_high 0
resetprop -n ro.eq.voltbl_id.btl_low 0
resetprop -n ro.eq.voltbl_id.se_high_amb 0
resetprop -n ro.eq.voltbl_id.se_high_nc 0

# High gain / DSD / NC Ambient
resetprop -n ro.app.highgain.mode 1
resetprop -n ro.dsd_pcm_conversion.filter 0
resetprop -n ro.dsd_pcm_conversion.gain 0
resetprop -n ro.nc_ambient.enabled true
resetprop -n ro.nc_ambient.environment 0
resetprop -n ro.nc_ambient.gain.amb 0
resetprop -n ro.nc_ambient.gain.nc 0

# Safe volume / AVLS
resetprop -n ro.safe_volume.enabled true
resetprop -n ro.safe_volume.default 0x50
resetprop -n ro.safe_volume.threshold.se.high 0x60
resetprop -n ro.safe_volume.threshold.se.normal 0x50
resetprop -n ro.safe_volume.threshold.btl.high 0x60
resetprop -n ro.safe_volume.threshold.btl.normal 0x50
resetprop -n ro.safe_volume.timer_count.limit 5
resetprop -n ro.safe_volume.timer_count.period 60
resetprop -n ro.safe_volume.alert_time.debug 0
resetprop -n ro.volume.avls.enabled true
resetprop -n ro.volume.avls.threshold.se.high 0x60
resetprop -n ro.volume.avls.threshold.se.normal 0x50
resetprop -n ro.volume.avls.threshold.btl.high 0x60
resetprop -n ro.volume.avls.threshold.btl.normal 0x50

# MTP / Updater / WiFi / Boot
resetprop -n ro.mtp.device.friendly_name NW-ZX500Series
resetprop -n ro.mtp.device.manufacturer "Sony Corporation"
resetprop -n ro.mtp.device.model NW-ZX507
resetprop -n ro.mtp.device.version 1.0
resetprop -n vendor.mtp.device.friendly_name NW-ZX500Series
resetprop -n vendor.mtp.device.manufacturer "Sony Corporation"
resetprop -n vendor.mtp.device.model NW-ZX507
resetprop -n vendor.mtp.device.version 1.0
resetprop -n ro.updater.product_id 0x310000
resetprop -n ro.updater.service_id 0x310000
resetprop -n ro.updater.vendor_id Sony
resetprop -n ro.updater.info NW-ZX500Series
resetprop -n ro.wifi.channel.index 0
resetprop -n ro.system.boot_mode 0
resetprop -n ro.bt.nvram.initflag 0
resetprop -n ro.app.forty.anniversary 0
#resetprop -n persist.vendor.izmprop.initialized true
resetprop -n persist.vendor.izmprop.initialized false
resetprop -n rw.app.nc.environment.param 0
resetprop -n rw.app.soundeffect.alert.flag 0
resetprop -n rw.app.storedemo.mode 0
resetprop -n rw.bt.settings.playback_quality 0

# ============================================================
# DEVICE NODES (i.MX UART stubs)
# ============================================================
for NODE in /dev/ttymxc0 /dev/ttymxc1 /dev/ttymxc2; do
  [ ! -e $NODE ] && mknod $NODE c 1 3 && chmod 0660 $NODE && chown 1002.1002 $NODE
done
[ ! -e /dev/trusty-ipc-dev0 ] && mknod /dev/trusty-ipc-dev0 c 1 3 && chmod 0660 /dev/trusty-ipc-dev0 && chown 1000.1026 /dev/trusty-ipc-dev0

# restart
if [ "$API" -ge 24 ]; then
  SERVER=audioserver
else
  SERVER=mediaserver
fi
killall $SERVER\
 android.hardware.audio@4.0-service-mediatek\
 android.hardware.audio.service

# ============================================================
# FDSAN FIX + BOOT WAIT
# ============================================================
resetprop debug.fdsan.error_level warn_once
resetprop -w sys.boot_completed 0

# ============================================================
# IDD DIRECTORY STRUCTURE
# ============================================================
mkdir -p /mnt/vendor/idd/output
mkdir -p /mnt/vendor/idd/socket
mkdir -p /mnt/vendor/idd/startup-prober
mkdir -p /mnt/vendor/idd/private
mkdir -p /mnt/vendor/idd/lost+found
mkdir -p /mnt/vendor/rca/plugins
chown 1000:1000 /mnt/vendor/idd 2>/dev/null; chmod 0751 /mnt/vendor/idd 2>/dev/null
chown 1000:1000 /mnt/vendor/idd/output 2>/dev/null; chmod 0755 /mnt/vendor/idd/output 2>/dev/null
chown 1000:1000 /mnt/vendor/idd/socket 2>/dev/null; chmod 0711 /mnt/vendor/idd/socket 2>/dev/null
chown 1000:1000 /mnt/vendor/idd/startup-prober 2>/dev/null; chmod 0700 /mnt/vendor/idd/startup-prober 2>/dev/null
chown 1000:1000 /mnt/vendor/rca/plugins 2>/dev/null; chmod 0750 /mnt/vendor/rca/plugins 2>/dev/null

# ============================================================
# NVP DRIVER / EMULATOR
# ============================================================
NVP_MODULE="$MODDIR/system/vendor/lib/modules/icx_nvp_emmc.ko"
NVP_LOADED=0
if [ -f "$NVP_MODULE" ]; then
    insmod "$NVP_MODULE" 2>/dev/null
    [ -e "/dev/icx_nvp/000" ] && NVP_LOADED=1
fi

if [ "$NVP_LOADED" = "0" ]; then
    NVP_EMU_DIR="$MODDIR/nvp_emulator"
    NVP_DATA_DIR="$NVP_EMU_DIR/nvp_data"
    mkdir -p "$NVP_DATA_DIR"

    # Generate NVP nodes (4-byte LE binary)
    if [ -x "$NVP_EMU_DIR/gen_nvp_binary.sh" ]; then
        sh "$NVP_EMU_DIR/gen_nvp_binary.sh" "$NVP_DATA_DIR" >> "$LOG" 2>&1
    else
        # Fallback: zero-fill
        i=0; while [ $i -le 242 ]; do
            zn=$(printf '%03d' $i)
            [ ! -f "$NVP_DATA_DIR/$zn" ] && printf '\x00\x00\x00\x00' > "$NVP_DATA_DIR/$zn"
            i=$((i + 1))
        done
    fi

    # Create /dev/icx_nvp symlinks
    rm -rf /dev/icx_nvp; mkdir -p /dev/icx_nvp
    i=0; while [ $i -le 242 ]; do
        zn=$(printf '%03d' $i)
#        ln -sf "$NVP_DATA_DIR/$zn" "/dev/icx_nvp/$zn" 2>/dev/null
        cp "$NVP_DATA_DIR/$zn" "/dev/icx_nvp/$zn" 2>/dev/null
        i=$((i + 1))
    done
    chmod 0777 /dev/icx_nvp/* 2>/dev/null
    chmod 0777 /dev/icx_nvp 2>/dev/null
fi

# ============================================================
# AUDIO HAL DETECTION & FALLBACK
# ============================================================
# Check which audio HAL is active

# ============================================================
# PROPERTY CONFLICT DETECTION
# ============================================================
# Check for conflicting properties that might prevent effects

# ============================================================
# IZM PROPERTIES HAL (fallback if init didn't start it)
# ============================================================
HAL_BIN_SYS="/vendor/bin/hw/izm.android.properties@1.0-service"
HAL_BIN_MOD="$MODDIR/system/vendor/bin/hw/izm.android.properties@1.0-service"
LDPATH="LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib"

# Check if IZM Properties HAL is already running

if [ "$(getprop init.svc.hw-properties-hal-1-0)" != "running" ]; then
  if [ -f "$HAL_BIN_SYS" ]; then
    nohup su system -c "$LDPATH $HAL_BIN_SYS" > /dev/null 2>&1 &
  elif [ -f "$HAL_BIN_MOD" ]; then
    chmod 0755 "$HAL_BIN_MOD"
    LDPATH_MOD="LD_LIBRARY_PATH=$MODDIR/system/vendor/lib64:$MODDIR/system/vendor/lib:/vendor/lib64:/vendor/lib"
    nohup su system -c "$LDPATH_MOD $HAL_BIN_MOD" > /dev/null 2>&1 &
  fi
fi

# ============================================================
# EFFECT INITIALIZATION DEBUG
# ============================================================
# Log effect-related property status for debugging

# ============================================================
# NVP WRAPPER TOOLS
# ============================================================
if [ -e "/dev/icx_nvp/000" ]; then
    NVP_EMU_DIR="$MODDIR/nvp_emulator"
#    mkdir -p "$MODDIR/system/vendor/bin"

    for tool in nvpnode; do
        cat > "$MODDIR/system/vendor/bin/$tool" << 'WRAPPER'
#!/system/bin/sh
NVP_EMU_DIR="PLACEHOLDER_NVP_EMU_DIR"
NVP_DATA_DIR="$NVP_EMU_DIR/nvp_data"

case "$0" in
    *nvpflag)
        HEX_MODE=0; ZONE=""; WRITE_DATA=""
        while [ $# -gt 0 ]; do
            case "$1" in -x) HEX_MODE=1; shift ;; *) [ -z "$ZONE" ] && ZONE="$1" || WRITE_DATA="$1"; shift ;; esac
        done
        case "$ZONE" in
            bmd) NODE="001";; prk) NODE="003";; tst) NODE="004";; gty) NODE="005";;
            mso) NODE="007";; nvr) NODE="012";; ins) NODE="014";;
            shp) NODE="022";; sid) NODE="023";; *) NODE="$ZONE";;
        esac
        if [ -n "$WRITE_DATA" ]; then
            echo -n "$WRITE_DATA" > "$NVP_DATA_DIR/$NODE"
        else
            VALUE=$(cat "$NVP_DATA_DIR/$NODE" 2>/dev/null || echo "00")
            [ $HEX_MODE -eq 1 ] && echo "0x$VALUE" || echo "$VALUE"
        fi ;;
    *nvpnode)
        i=0; while [ $i -le 242 ]; do
            NODE=$(printf '%03d' $i)
            VALUE=$(cat "$NVP_DATA_DIR/$NODE" 2>/dev/null || echo "00")
            [ "$VALUE" != "00" ] && [ -n "$VALUE" ] && echo "  $NODE: $VALUE"
            i=$((i + 1))
        done ;;
    *nvpinfo) echo "NVP Emulated (243 nodes)" ;;
    *nvpstr) NODE=$1; shift; [ $# -gt 0 ] && echo -n "$*" > "$NVP_DATA_DIR/$NODE" || cat "$NVP_DATA_DIR/$NODE" 2>/dev/null ;;
    *nvp) echo "NVP nodes: $(ls -1 $NVP_DATA_DIR | wc -l)" ;;
esac
WRAPPER
        sed -i "s|PLACEHOLDER_NVP_EMU_DIR|$NVP_EMU_DIR|" "$MODDIR/system/vendor/bin/$tool"
        chmod 0755 "$MODDIR/system/vendor/bin/$tool"
    done
fi

# ============================================================
# PERMISSIONS
# ============================================================
chmod 0755 $MODDIR/system/bin/*
[ "$API" -ge 26 ] && chown 0.2000 $MODDIR/system/bin/*

chmod 0755 $MODDIR$MODSYSTEM/vendor/bin/hw/*
chown 0.2000 $MODDIR$MODSYSTEM/vendor/bin/hw/*

# ============================================================
# SONY-SPECIFIC SERVICES (skip on non-Sony devices)
# ============================================================

# ============================================================
# IDD DAEMON
# ============================================================
IDD_BIN="/vendor/bin/iddd"
if [ -f "$IDD_BIN" ]; then
    # Create idd-logreader stub (prevents CPU spin on unsupported kernel)
    LOGREADER_STUB="$MODDIR/system/vendor/bin/idd-logreader"
    if [ ! -f "$LOGREADER_STUB" ]; then
#        mkdir -p "$MODDIR/system/vendor/bin"
#        printf '#!/system/bin/sh\nexit 0\n' > "$LOGREADER_STUB"
        chmod 0755 "$LOGREADER_STUB"
    fi
    killall iddd 2>/dev/null
    nohup "$IDD_BIN" > /dev/null 2>&1 &
    sleep 1
fi

# IDD HIDL service
SERVICES=$(realpath /vendor)/bin/hw/vendor.semc.system.idd@1.0-service
for SERVICE in $SERVICES; do
    killall $SERVICE 2>/dev/null
    nohup $SERVICE > /dev/null 2>&1 &
done

# Permissions
chmod 0755 $MODDIR$MODSYSTEM/vendor/bin/*
chown 0.2000 $MODDIR$MODSYSTEM/vendor/bin/*
chmod 0755 $MODDIR$MODSYSTEM/vendor/xbin/*
chown 0.2000 $MODDIR$MODSYSTEM/vendor/xbin/*

# Load drivers — fallback ONLY. init.rc (init.icx1295.rc) already starts
# load_sony_driver @ early-init and icx_early_init_sh @ on fs. Gate on the
# props init.rc sets so we never double-insmod icx_nvp_emmc.ko (race/fixable
# selftest failure). If init.rc didn't fire (bare OnePlus port), service.sh
# performs the load here.
if [ "$(getprop sys.all.early_init.ready)" != "1" ]; then
    init.insmod.sh /vendor/etc/early.init.cfg sys.all.early_init.ready
    load_sony_driver sys.all.early_init.ready
fi
if [ "$(getprop vendor.load_nvp_driver.done)" != "1" ]; then
    init.insmod.sh /vendor/etc/icx_early.init.cfg vendor.load_nvp_driver.done
    setprop vendor.load_nvp_driver.done 1
fi

# ============================================================
# ERRR WORKAROUND — re-apply identity props after HAL init
# ============================================================
i=0
while [ $i -lt 15 ]; do
  [ "$(getprop persist.vendor.izmprop.initialized)" = "true" ] && break
  [ "$(getprop init.svc.hw-properties-hal-1-0)" = "stopped" ] && break
  sleep 1
  i=$((i+1))
done

# Use 0x310000 consistently (LE: 00 00 31 00)
resetprop vendor.model_id 0x310000
resetprop vendor.body_color 0
resetprop vendor.destination 259
resetprop vendor.service_id 512
resetprop vendor.safe_volume.enabled 1
resetprop ro.product.body_color 0

# Volume table (skipped on non-Sony HW — no CXD3778GF proc entries)
[ -d /proc/icx_audio_cxd3778gf_data ] && load_volume_table 0

resetprop -n vendor.sony.log_zip true
if command -v icx_syslog >/dev/null 2>&1; then
  nohup icx_syslog -n 32 -l 6 -d "/mnt/vendor/var" >/dev/null 2>&1 &
else
  echo "[warn] icx_syslog not found in module/system/vendor/bin — skipped" >> "$LOG"
fi
filezip.sh
resetprop -p --delete vendor.sony.log_zip

# Wait for boot completed (with timeout)
i=0
while [ "$i" -lt 30 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i+1))
done

# Final identity fix (HAL may have overwritten with "errr")
resetprop vendor.model_id 0x310000
resetprop vendor.body_color 0
resetprop vendor.destination 259
resetprop vendor.service_id 512
resetprop vendor.safe_volume.enabled 1
resetprop ro.product.body_color 0

# ============================================================
# AUDIO EFFECTS OVERLAY
# ============================================================
# Override audio_effects.xml to include Sony-style effects
# /vendor/etc is read-only on some devices, use bind mount

# list
PKGS="`cat $MODPATH/package.txt`
       com.miui.rom:ui"
for PKG in $PKGS; do
  magisk --denylist rm $PKG 2>/dev/null
  magisk --sulist add $PKG 2>/dev/null
done
if magisk magiskhide sulist; then
  for PKG in $PKGS; do
    magisk magiskhide add $PKG
  done
else
  for PKG in $PKGS; do
    magisk magiskhide rm $PKG
  done
fi

# function
stop_log() {
SIZE=`du $LOGFILE | sed "s|$LOGFILE||g"`
if [ "$LOG" != stopped ] && [ "$SIZE" -gt 50 ]; then
  exec 2>/dev/null
  set +x
  LOG=stopped
fi
}
check_audioserver() {
if [ "$NEXTPID" ]; then
  PID=$NEXTPID
else
  PID=`pidof $SERVER`
fi
sleep 15
stop_log
NEXTPID=`pidof $SERVER`
[ "$PID" != "$NEXTPID" ] && killall $PROC
#check_audioserver
}
check_service() {
for SERVICE in $SERVICES; do
  if ! pidof $SERVICE; then
    $SERVICE &
    PID=`pidof $SERVICE`
  fi
done
}

# check
#check_service
#PROC=com.sonyericsson.soundenhancement
#PROC="com.sonyericsson.soundenhancement com.sony.walkman.soundeffectapp jp.co.sony.threesixtyra.system"
#PROC=com.sony.walkman.soundeffectapp
#killall $PROC
#check_audioserver











