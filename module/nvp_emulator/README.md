# NVP Emulator for ICX1295 on Non-Sony Hardware

## Problem
The Sony ICX1295 (NW-ZX505/ZX507) uses a kernel module (`icx_nvp_emmc.ko`) to provide access to the NVRAM partition via `/dev/icx_nvp/NNN` character devices. On non-Sony hardware (like OnePlus 3), this kernel module cannot be loaded because:
1. The kernel doesn't have `CONFIG_MODULES=y`
2. The module is compiled for a different kernel version (4.14.78 vs 3.18.124)
3. The module is compiled for a different architecture (i.MX8M Mini vs MSM8996)

## Solution
This NVP emulator provides a userspace solution that creates `/dev/icx_nvp/NNN` entries using regular files and symlinks. While not a perfect replacement for the kernel module, it provides compatibility with Sony tools and the IZM Properties HAL.

## Components

### Overview — 8 skriptů (+ 1 gitrojený binární helper `nvp_fuse_helper`)

> ⚠️ **Wiring status:** tento toolkit je **přítom, ale nezapojen** do boot chainu.
> `customize.sh` a `service.sh` volají **pouze** `gen_nvp_binary.sh`. Ostatní 7 skriptů
> (`nvp_emulator.sh`, `init_nvp.sh`, `nvp_wrapper.sh`, `nvp_daemon.sh`,
> `setup_nvp_emulator.sh`, `nvp_fuse.sh`, `integrate_with_service.sh`) **nikdy nejsou volány**
> z `customize.sh`/`post-fs-data.sh`/`service.sh` (verify: `grep -rn`). `nvp_fuse_helper` (binární)
> je gitignored → chybí v buildnutém ZIPu. Viz `docs/MODULE_ARCHITECTURE.md` §5.4.

| # | script | role |
|---|--------|------|
| 0 | `gen_nvp_binary.sh` | Generuje 243 NVP nodů (4-byte LE) z lookup tabulky `libizmproperties.so`. Jediný zdroj pravdy pro NVP data. |
| 1 | `nvp_emulator.sh` | Hlavní userspace emulace: `init`/`read`/`write`/`stat`/`eraseall` + vytváří `/dev/icx_nvp/NNN`. |
| 2 | `init_nvp.sh` | Vestavěný init wrapper volaný `nvp_emulator.sh init`; naplní defaulty + node 022 = model ID. |
| 3 | `nvp_wrapper.sh` | Přesměrování Sony nástrojů (`nvpflag`/`nvpnode`/`nvpinfo`/`nvpstr`/`nvp`) na emulator. |
| 4 | `nvp_daemon.sh` | Persistentní daemon: udržuje `/dev/icx_nvp/`, restartuje při změně stanz; `start`/`stop`/`status`/`restart`. |
| 5 | `setup_nvp_emulator.sh` | Instalace do module dir + symlinky wrapperů do `$PATH` + první `init`. |
| 6 | `nvp_fuse.sh` | Volitelný FUSE overlay — char-device kompatibilita (ioctl) pro tooling, které nebereme jako běžný soubor. |
| 7 | `integrate_with_service.sh` | Připojení emulátoru k `service.sh`/`post-fs-data.sh` timeline (volání před IZM HAL). |

> `gen_nvp_binary.sh` není součástí runtime emulace — je to **generátor NVP dat**. Spouští se jen během build/development (viz hlavní walkman-port-playbook). Nikdy nevkládat výstup (`nvp_data/`) do gitu.

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

### 5. gen_nvp_binary.sh (install-time + boot fallback)
Generates the 243 NVP nodes as 4-byte little-endian values from the `libizmproperties.so`
property info table (parsed at `0x00cbd0`). Output target dir je výchozím `nvp_data/`.
Jediný skript z toolkitu, který se skutečně spouští — volán z `customize.sh:18` (instalace)
a jako fallback z `service.sh:237` (pokud `nvp_data/` chybí).
Critical nodes: `000`=version(1), `018`=ModelID(`0x31000000` ZX507 CEW),
`019`=Serial(`"1234"`), `022`=Destination(`0x00000103` CEW), `033`=BT initflag, `124`=AVLS enabled.

### 6. init_nvp.sh
Boot-time initializer invoked by `nvp_emulator.sh init`. Seeds default node images
and is responsible for writing node `018` (ModelID) + `022` (Destination) so the IZM
Properties HAL reads the correct device identity before binding.

### 7. nvp_fuse.sh (optional)
FUSE-backed `/dev/icx_nvp/NNN` char-device shim. Použije se jen pokud běžící tool
vyžaduje `ioctl`/`select`/`poll` na char device (běžné soubory tím neprojdou).
Vyžaduje `fuse` kernel modul — na msm8996 3.18 sice dostupný, ale nejlépe potvrdit
v logcatu před použitím.

## Wiring / installation — ⚠️ nezapojený do bootu

`nvp_emulator/` **není** automaticky aktivován při flašování modulu. Během instalace
(`customize.sh`) se spustí **pouze** `gen_nvp_binary.sh`, který vygeneruje
`nvp_emulator/nvp_data/{000..242}`. Wrapper skripty (`nvpflag`/`nvpnode`/`nvpinfo`/`nvpstr`/`nvp`)
a daemon (`nvp_daemon.sh`) **nejsou** do boot chainu zapojeny — viz `docs/MODULE_ARCHITECTURE.md` §5.4.

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
