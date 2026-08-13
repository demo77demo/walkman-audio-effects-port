# NVP Emulator for ICX1295 on Non-Sony Hardware

## Problem
The Sony ICX1295 (NW-ZX505/ZX507) uses a kernel module (`icx_nvp_emmc.ko`) to provide access to the NVRAM partition via `/dev/icx_nvp/NNN` character devices. On non-Sony hardware (like OnePlus 3), this kernel module cannot be loaded because:
1. The kernel doesn't have `CONFIG_MODULES=y`
2. The module is compiled for a different kernel version (4.14.78 vs 3.18.124)
3. The module is compiled for a different architecture (i.MX8M Mini vs MSM8996)

## Solution
This NVP emulator provides a userspace solution that creates `/dev/icx_nvp/NNN` entries using regular files and symlinks. While not a perfect replacement for the kernel module, it provides compatibility with Sony tools and the IZM Properties HAL.

## Components

### 1. nvp_emulator.sh
Main emulator script that:
- Initializes NVP data directory with default values
- Creates `/dev/icx_nvp/` device nodes
- Provides read/write/stat/eraseall operations

### 2. nvp_wrapper.sh
Wrapper script that intercepts Sony NVP tools and redirects them to the emulator:
- `nvpflag` - Read/write NVP flags
- `nvpnode` - Get node information
- `nvpinfo` - Read NVP information
- `nvpstr` - Read/write NVP strings
- `nvp` - General NVP operations

### 3. nvp_daemon.sh
Persistent daemon that:
- Keeps NVP emulator running in background
- Maintains `/dev/icx_nvp/` device nodes
- Handles cleanup on module uninstall

### 4. setup_nvp_emulator.sh
Installation script that:
- Copies emulator scripts to module directory
- Creates wrapper scripts for Sony NVP tools
- Initializes NVP data

## Installation

### Automatic (via Magisk module)
The NVP emulator is automatically installed when the Magisk module is flashed. The setup script creates wrapper scripts that replace the Sony NVP tools.

### Manual
```bash
# Copy emulator files to module directory
cp -r nvp_emulator/ /data/adb/modules/icx1295_audio_hal/

# Run setup
/data/adb/modules/icx1295_audio_hal/nvp_emulator/setup_nvp_emulator.sh

# Start daemon
/data/adb/modules/icx1295_audio_hal/nvp_emulator/nvp_daemon.sh start
```

## Usage

### Using Sony Tools (via wrappers)
```bash
# Read NVP flag
nvpflag bmd

# Write NVP flag
nvpflag bmd 01

# Show NVP statistics
nvpnode

# Read NVP string
nvpstr 019
```

### Using Emulator Directly
```bash
# Initialize NVP
nvp_emulator.sh init

# Read node
nvp_emulator.sh read 019

# Write node
nvp_emulator.sh write 019 "00000000"

# Show statistics
nvp_emulator.sh stat

# Erase all data
nvp_emulator.sh eraseall
```

## NVP Node Map
Based on Sony firmware analysis:

| Node | Description | Default |
|------|-------------|---------|
| 000 | Version | 00 |
| 001 | Boot mode flag | 00 |
| 003 | Printk flag | 00 |
| 004 | Test mode flag | 00 |
| 005 | Getty mode flag | 00 |
| 007 | MSC only mode flag | 00 |
| 012 | NVRAM init flag | 00 |
| 014 | Install flag | 00 |
| 018 | Model ID | 00 |
| 019 | Serial number | 00 |
| 020 | Product code | 00 |
| 021 | Body color | 00 |
| 022 | Destination | 00 |
| 023 | User destination | 00 |
| 024 | Bundled HP | 00 |
| 025 | eMMC capacity | 00 |
| 026 | SKU UPID | 00 |
| 027 | Product ID | 00 |
| 028 | Service ID | 00 |
| 029 | USB manufacturer name | 00 |
| 030 | USB product name | 00 |
| 031 | WiFi channel index | 00 |
| 032 | Boot mode | 00 |
| 033 | BT NVRAM initflag | 00 |
| 034 | Region data version | 00 |
| 035 | User install flag | 00 |
| 064 | Volume default | 00 |
| 065 | Volume default SE high | 00 |
| 066 | Volume default SE normal | 00 |
| 067 | Volume default BTL high | 00 |
| 068 | Volume default BTL normal | 00 |
| 069 | Volume gain SE | 00 |
| 082 | ALC voltbl ID SE high | 00 |
| 083 | ALC voltbl ID SE low | 00 |
| 084 | ALC voltbl ID BTL high | 00 |
| 085 | ALC voltbl ID BTL low | 00 |
| 086 | ALC voltbl ID SE high amb | 00 |
| 087 | ALC voltbl ID SE high NC | 00 |
| 088 | EQ voltbl ID SE high | 00 |
| 089 | EQ voltbl ID SE low | 00 |
| 090 | EQ voltbl ID BTL high | 00 |
| 091 | EQ voltbl ID BTL low | 00 |
| 092 | EQ voltbl ID SE high amb | 00 |
| 093 | EQ voltbl ID SE high NC | 00 |

## Limitations

1. **File-based emulation**: Uses regular files instead of char devices
   - No ioctl support (some tools may fail)
   - No proper blocking/non-blocking behavior
   - No proper select/poll support

2. **No persistence**: NVP data is stored in module directory
   - Data survives reboots (Magisk module persists)
   - Data is lost if module is uninstalled

3. **No allocation table**: Simplified storage model
   - No sector/cluster allocation
   - No wear leveling
   - No bad sector management

## Integration with Magisk Module

The NVP emulator integrates with the existing Magisk module by:
1. Creating wrapper scripts that replace Sony NVP tools
2. Providing `/dev/icx_nvp/` device nodes before IZM HAL starts
3. Maintaining NVP data in the module directory

## Troubleshooting

### Check if emulator is running
```bash
nvp_daemon.sh status
```

### Check NVP data
```bash
nvp_emulator.sh stat
```

### Check wrapper logs
```bash
cat /data/adb/modules/icx1295_audio_hal/nvp_emulator/wrapper.log
```

### Restart emulator
```bash
nvp_daemon.sh restart
```

## Future Improvements

1. **FUSE-based emulation**: Proper char device emulation using FUSE
2. **Socket-based daemon**: Better IPC for NVP requests
3. **Property integration**: Use Android properties for NVP storage
4. **ioctl support**: Implement common ioctl commands
5. **Allocation table**: Implement proper sector/cluster allocation

## References

- Sony ICX1295 NVP partition analysis
- Linux kernel module interface
- Magisk module system
- Android property system
