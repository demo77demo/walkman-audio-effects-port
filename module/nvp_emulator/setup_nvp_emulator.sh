#!/system/bin/sh
# Setup NVP Emulator for ICX1295 Magisk Module
# This script installs the NVP emulator and creates wrapper scripts

MODDIR=${0%/*}
NVP_EMU_DIR="$MODDIR/nvp_emulator"
NVP_BIN_DIR="$MODDIR/system/vendor/bin"
NVP_DATA_DIR="$NVP_EMU_DIR/nvp_data"

echo "Setting up NVP Emulator..."

# Create directories
mkdir -p "$NVP_EMU_DIR"
mkdir -p "$NVP_BIN_DIR"
mkdir -p "$NVP_DATA_DIR"

# Copy emulator scripts
cp "$NVP_EMU_DIR/nvp_emulator.sh" "$NVP_EMU_DIR/"
chmod 0755 "$NVP_EMU_DIR/nvp_emulator.sh"

cp "$NVP_EMU_DIR/nvp_wrapper.sh" "$NVP_EMU_DIR/"
chmod 0755 "$NVP_EMU_DIR/nvp_wrapper.sh"

# Create wrapper scripts for Sony NVP tools
for tool in nvpflag nvpnode nvpinfo nvpstr nvp; do
    cat > "$NVP_BIN_DIR/$tool" << EOF
#!/system/bin/sh
exec $NVP_EMU_DIR/nvp_wrapper.sh "\$@"
EOF
    chmod 0755 "$NVP_BIN_DIR/$tool"
    echo "Created wrapper: $NVP_BIN_DIR/$tool"
done

# Initialize NVP data
"$NVP_EMU_DIR/nvp_emulator.sh" init

echo "NVP Emulator setup complete"
echo "Data directory: $NVP_DATA_DIR"
echo "Device directory: /dev/icx_nvp"
