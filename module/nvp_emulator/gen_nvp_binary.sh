#!/system/bin/sh
# gen_nvp_binary.sh - generate NVP node data as 4-byte LITTLE-ENDIAN binary.
#
# AUTHORITATIVNÍ MAPOVÁNÍ: Extrahováno přímo z libizmproperties.so
# (sony-imx8mm-icx1295 firmware, vendor/lib64/libizmproperties.so)
# Metoda: Parsing property info table (144-byte entries) z .rodata sekce
#
# FIX B1 (verified live OP3 2026-07-16):
#   libizmproperties.so nvp_read: "cmp w0,#4" -> expects exactly 4 bytes.
#   Sony IzmPropertiesHelper.fromByteToInt: ByteBuffer.wrap(b).order(LE).getInt() -> 4 bytes.
#
# Usage: sh gen_nvp_binary.sh [output_dir]
# Default output: ./nvp_data/
MODDIR=${0%/*}
NVP_DATA_DIR="${1:-$MODDIR/nvp_data}"
mkdir -p "$NVP_DATA_DIR"

# write 4-byte LE binary for decimal/hex value $2 into node file $1
write_node() {
    local node=$(echo "$1" | sed 's/^0*//' | sed 's/^$/0/')
    local val="$2"
    local f="$NVP_DATA_DIR/$(printf "%03d" "$node")"
    if echo "$val" | grep -qi "^0x"; then val=$((val)); fi
    local b0=$((val & 0xFF)) b1=$(((val >> 8) & 0xFF)) b2=$(((val >> 16) & 0xFF)) b3=$(((val >> 24) & 0xFF))
    # Portable on Android /system/bin/sh: toybox printf interprets \xNN to one
    # byte. Old `printf '%b' "$(printf '\\\\xNN')"` emitted 16-byte literal text
    # under toybox/mksh -> violated FIX B1 (cmp w0,#4). Verified on host sh.
    printf '%b' "$(printf '\\%03o\\%03o\\%03o\\%03o' "$b0" "$b1" "$b2" "$b3")" > "$f"
}

# write 4 ASCII bytes into node file $1 from string $2
write_str4() {
    local node=$(echo "$1" | sed 's/^0*//' | sed 's/^$/0/')
    local str="$2"
    local f="$NVP_DATA_DIR/$(printf "%03d" "$node")"
    local s=$(echo -n "$str" | head -c 4)
    local len=${#s}
    local b0=0 b1=0 b2=0 b3=0
    [ $len -ge 1 ] && b0=$(printf '%d' "'$(echo "$s" | cut -c1)")
    [ $len -ge 2 ] && b1=$(printf '%d' "'$(echo "$s" | cut -c2)")
    [ $len -ge 3 ] && b2=$(printf '%d' "'$(echo "$s" | cut -c3)")
    [ $len -ge 4 ] && b3=$(printf '%d' "'$(echo "$s" | cut -c4)")
    # Portable on Android /system/bin/sh: toybox printf interprets \xNN to one
    # byte. Old `printf '%b' "$(printf '\\\\xNN')"` emitted 16-byte literal text
    # under toybox/mksh -> violated FIX B1 (cmp w0,#4). Verified on host sh.
    printf '%b' "$(printf '\\%03o\\%03o\\%03o\\%03o' "$b0" "$b1" "$b2" "$b3")" > "$f"
}

# Default all 243 nodes to 0
i=0
while [ $i -le 242 ]; do
    write_node $i 0
    i=$((i + 1))
done

# ============================================================
# CRITICKÉ NVP NODY (mimo property tabulku, ale potřebné pro NVP tools)
# ============================================================
write_node   0  1              # version (NVP format version)
write_node  18  0x31000000     # _MODEL_ID_ (NW-ZX507, CEW) — raw NVP node
write_str4  19  "1234"         # _SER_ serial number
write_str4  20  "1234"         # _PCD_ product code
write_node  21  0xFFFFFFFF     # _CLV_ body_color NOCOLOR
write_node  22  0x00000103     # shp destination CEW
write_node  23  0x00000200     # sid user_destination CEW
write_node  24  0x4E4F4850     # _SPS_ bundled_hp NOHP
write_node  25  32             # emmc_capacity (32GB)
write_node  26  0x310000       # sku_upid
write_node  27  0x310000       # product_id
write_node  28  512            # service_id
write_str4  29  "Sony"         # _UMS_ USB manufacture name
write_str4  30  "WALK"         # _UPS_ USB product name
write_node  34  1              # regiondata.version
write_node  35  1              # user.install.flag

# ============================================================
# AUTHORITATIVNÍ MAPOVÁNÍ (z libizmproperties.so parsing)
# Pořadí dle výskytu v property info table (0x00cbd0)
# ============================================================

# --- ALC Volume Table IDs ---
write_node 198  0              # ro.alc.voltbl_id.btl_high
write_node 197  0              # ro.alc.voltbl_id.btl_low
write_node 194  0              # ro.alc.voltbl_id.se_high
write_node 196  0              # ro.alc.voltbl_id.se_high_amb
write_node 195  0              # ro.alc.voltbl_id.se_high_nc
write_node 193  0              # ro.alc.voltbl_id.se_low

# --- App flags ---
write_node 112  0              # ro.app.forty.anniversary
write_node 111  0              # ro.app.highgain.mode

# --- BT / System ---
write_node 077  0              # ro.bt.nvram.initflag

# --- ClearPhase file paths (string pointers, stored as 0) ---
write_node 203  0              # ro.clear_phase.filepath.lps_176400
write_node 204  0              # ro.clear_phase.filepath.lps_192000
write_node 199  0              # ro.clear_phase.filepath.lps_44100
write_node 200  0              # ro.clear_phase.filepath.lps_48000
write_node 201  0              # ro.clear_phase.filepath.lps_88200
write_node 202  0              # ro.clear_phase.filepath.lps_96000

# --- DSD / DSEE ---
write_node 152  0              # ro.dsd_pcm_conversion.filter
write_node 153  0              # ro.dsd_pcm_conversion.gain
write_node 206  0              # ro.dsee_ai.filepath.bin
write_node 205  0              # ro.dsee_ai.filepath.dcfg

# --- Dynamic Normalizer ---
write_node 159  0              # ro.dynamic_normalizer.mode

# --- Audio Effects (enabled flags) ---
write_node 147  1              # ro.effect.clear_audio_plus.enabled
write_node 137  1              # ro.effect.clear_phase.enabled
write_node 142  1              # ro.effect.dc_phase_linearizer.enabled
write_node 143  0              # ro.effect.dc_phase_linearizer.type
write_node 138  1              # ro.effect.dsee_ai.enabled
write_node 139  1              # ro.effect.dynamic_normalizer.enabled
write_node 140  1              # ro.effect.equalizer_10.enabled
write_node 141  0              # ro.effect.equalizer_10.preset
write_node 146  1              # ro.effect.source_direct.enabled
write_node 144  1              # ro.effect.vinyl_processor.enabled
write_node 145  0              # ro.effect.vinyl_processor.type

# --- EQ Volume Table IDs ---
write_node 213  0              # ro.eq.voltbl_id.btl_high
write_node 212  0              # ro.eq.voltbl_id.btl_low
write_node 209  0              # ro.eq.voltbl_id.se_high
write_node 211  0              # ro.eq.voltbl_id.se_high_amb
write_node 210  0              # ro.eq.voltbl_id.se_high_nc
write_node 208  0              # ro.eq.voltbl_id.se_low

# --- MTP Device Info (string nodes) ---
write_str4 215  "NW-ZX"       # ro.mtp.device.friendly_name = "NW-ZX500Series"
write_str4 216  "Sony"        # ro.mtp.device.manufacturer = "Sony Corporation"
write_str4 217  "NW-ZX"       # ro.mtp.device.model = "NW-ZX507"
write_str4 218  "1.0\0"       # ro.mtp.device.version = "1.0"

# --- NC Ambient ---
write_node 148  1              # ro.nc_ambient.enabled
write_node 149  0              # ro.nc_ambient.environment
write_node 151  0              # ro.nc_ambient.gain.amb
write_node 150  0              # ro.nc_ambient.gain.nc

# --- Product Identity ---
write_node 068  0              # ro.product.body_color
write_node 069  0              # ro.product.bundled_hp
write_node 012  0x3            # ro.product.destination (CEW)
write_node 007  0x310000       # ro.product.model_id
write_str4 008  "1234"         # ro.product.product_code
write_str4 009  "1234"         # ro.product.serial_number
write_str4 027  "Sony"         # ro.product.usb_manufacture_name
write_str4 029  "WALK"         # ro.product.usb_product_name

# --- Region / Install ---
write_node 093  1              # ro.regiondata.version
write_node 095  0x3            # ro.user.destination (CEW)
write_node 094  1              # ro.user.install.flag

# --- Safe Volume ---
write_node 081  0              # ro.safe_volume.alert_time.debug
write_node 130  0x50           # ro.safe_volume.default
write_node 129  1              # ro.safe_volume.enabled
write_node 134  0x60           # ro.safe_volume.threshold.btl.high
write_node 133  0x50           # ro.safe_volume.threshold.btl.normal
write_node 132  0x60           # ro.safe_volume.threshold.se.high
write_node 131  0x50           # ro.safe_volume.threshold.se.normal
write_node 136  5              # ro.safe_volume.timer_count.limit
write_node 135  60             # ro.safe_volume.timer_count.period

# --- System ---
write_node 003  0              # ro.system.boot_mode

# --- Updater ---
write_node 011  0              # ro.updater.info
write_node 033  0              # ro.updater.product_id
write_node 083  0              # ro.updater.service_id
write_node 031  0              # ro.updater.vendor_id

# --- Vinyl Processor ---
write_node 214  0              # ro.vinylprocessor.filepath.vinylcoeff

# --- Volume ---
write_node 124  1              # ro.volume.avls.enabled
write_node 128  0x60           # ro.volume.avls.threshold.btl.high
write_node 127  0x50           # ro.volume.avls.threshold.btl.normal
write_node 126  0x60           # ro.volume.avls.threshold.se.high
write_node 125  0x50           # ro.volume.avls.threshold.se.normal
write_node 121  0x70           # ro.volume.default
write_node 158  0x70           # ro.volume.default.btl.high
write_node 157  0x70           # ro.volume.default.btl.normal
write_node 156  0x70           # ro.volume.default.se.high
write_node 155  0x70           # ro.volume.default.se.normal
write_node 123  0              # ro.volume.gain.btl
write_node 122  0              # ro.volume.gain.se

# --- WiFi ---
write_node 154  0              # ro.wifi.channel.index

echo "NVP binary generated: $(ls -1 "$NVP_DATA_DIR" | wc -l) nodes, 4-byte LE"
echo "Source: libizmproperties.so property info table (84 properties, 88 NVP nodes)"
