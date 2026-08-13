#!/system/bin/sh
# NVP emulator init - creates symlinks only (data files pre-generated in customize.sh)
MODDIR=${0%/*}
NVP_EMU_DIR="$MODDIR"
NVP_DATA_DIR="$NVP_EMU_DIR/nvp_data"
LOG="${MODDIR}/../debug.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') init_nvp: START" >> "$LOG" 2>/dev/null

# If data files don't exist, generate them (fallback for manual installation)
if [ ! -f "$NVP_DATA_DIR/000" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') init_nvp: NVP data missing, generating..." >> "$LOG" 2>/dev/null
    chmod 0755 "$NVP_EMU_DIR/gen_nvp_binary.sh" 2>/dev/null
    sh "$NVP_EMU_DIR/gen_nvp_binary.sh" "$NVP_DATA_DIR" >> "$LOG" 2>&1
fi

# Verify
NODE0=$(cat "$NVP_DATA_DIR/000" 2>/dev/null | od -A n -t x1 | tr -d ' ')
NODE22=$(cat "$NVP_DATA_DIR/022" 2>/dev/null | od -A n -t x1 | tr -d ' ')
NODE138=$(cat "$NVP_DATA_DIR/138" 2>/dev/null | od -A n -t x1 | tr -d ' ')
echo "$(date '+%Y-%m-%d %H:%M:%S') init_nvp: VERIFY 000=$NODE0 022=$NODE22 138=$NODE138" >> "$LOG" 2>/dev/null

# Create symlinks
rm -rf /dev/icx_nvp 2>/dev/null
mkdir -p /dev/icx_nvp 2>/dev/null
i=0
while [ $i -le 242 ]; do
    node=$(printf '%03d' $i)
#    ln -sf "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node" 2>/dev/null
    cp "$NVP_DATA_DIR/$node" "/dev/icx_nvp/$node" 2>/dev/null
    i=$((i + 1))
done
chmod 0777 /dev/icx_nvp/* 2>/dev/null
chmod 0777 /dev/icx_nvp 2>/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') init_nvp: done (symlinks created)" >> "$LOG" 2>/dev/null
