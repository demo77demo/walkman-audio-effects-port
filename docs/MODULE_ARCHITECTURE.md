# Walkman Audio Effects Port — Magisk Module Architecture

**Scope:** deep analysis of the live Magisk module in `module/`. Answering: *how does this module
actually work on Android 11 / OnePlus 3 (msm8996), file-by-file and lifecycle-by-lifecycle.*

> Note on sources: external dokumentace (topjohnwu/Magisk `docs/modules.md`, `magisk.danty.in`)
> byla nedostupní (404 / DNS). Magisk konstrukce je zde použita jako **navodňený model**
> (verzně stabilní od Magisk 23 do 28) a **podložená konkrétním obsahem** každého skriptu
> v `module/`. Každý technický výrok má odkaz na konkrétní soubor+konkretňák.

---

## 0. Orientace (rychlý tah)

- **`module/` = jedinná source of truth** pro build. `module/system/` uvnitř je **gitignored**
  (viz `.gitignore`) — je to *flash-time payload* (Sony proprietární binárky), ne source.
  Nesnaž se ho "upravovat jako source". Používej ho jen read-only jako referenční snapshot.
- **Tři fáze života modulu:** `customize.sh` (instalace, jednorázově) →
  `post-fs-data.sh` (brzy po bootu) → `service.sh` (později po bootu).
- **Dvě NVP implementace** (viz §5): inline v `post-fs-data.sh`/`service.sh` (aktivní, běží)
  a `module/nvp_emulator/` (plnější toolkit, aktuálně *nepojatý* do řetězce bootu).
- **Audio effects se netapí přes `soundfx/`** (adresář prázdný — viz §6). Zapínají se přes
  modifikovaný `audio.primary.msm8996.so` + sadu resetprop + Sony APK.
- **GNU/GNU userspace na Bionicu** (viz §7): `bin/{fusermount,openssl,idds,...}` +
  `lib/aarch64-linux-gnu/{libc-2.25.so,...}` + `recreate_symlinks.sh`. To je nejtěžší část portu.

---

## 1. Autoritativní model Magisk modulu (Android 11)

### 1.1 Co Magisk dělá s modulem (instalace)
1. Magisk app / `magisk install-module` rozbalí ZIP → dočasný `MODPATH`.
2. Načte `module.prop` (id/name/version/code/author/description).
3. Spustí `META-INF/com/google/android/update-binary` s env:
   `$MODPATH`, `$ZIPFILE`, `$TMPDIR`, `$ARCH`, `$IS64BIT`, `$DEVICE`, `$DEVICENAME`,
   `$MODEL`, `$MANUFACTURER`, `$SLOTA`/`$SLOT`, `$BOOTMODE`, `$MAGISK_VER`, `$MAGISK_VER_CODE`,
   `$SAFETYNET`, `$MIRROR`.
   - `update-binary` má v sobě *vestavěné helpery*: `ui_print`, `set_perm`,
   `set_perm_recursive`, `replace_file`, `add_sepolicy`, `magiskpolicy` (a v novějších
   `resetprop`, `mount_odm`, `mount_my_product`, … — právě ty používá `post-fs-data.sh`).
4. Standardní `update-binary` zkopíruje strom `system/` (a `vendor/`, `product/`, …)
   do `$MODPATH`, pak `MODPATH` → `/data/adb/modules/<id>/`. Pak se spustí `customize.sh`.
5. Magisk **nesmaže** `system/` obsah; jen ho *magic-mount*uje přes overlayfs na reálný
   `/system`, `/vendor`, … (tzv. *magic mount*, nebo v režimu `nomount` bind-mount přes
   `$MODPATH`/system). `service.sh`/`post-fs-data.sh` pak běží s `MODDIR=/data/adb/modules/<id>`.

### 1.2 Co tento modul dělá s `update-binary`
`module/META-INF/com/google/android/update-binary` je **jen stub `exit 0`** a
`updater-script` je jen `1`.

→ Modul **není určen na flash přes TWRP**. Instalace proběhne přes Magisk app /
`magisk install-module`, která **ignoruje** tento stub a použije svůj vlastní installer,
který **skutečně** spustí `customize.sh` + nastaví `set_perm`. Všechny instalační
věci (gen NVP, permisse) žijí v `customize.sh`, ne v `update-binary`.

**Pitfall:** Pokud někdo flashne ZIP přes TWRP až s tímto stubem, `customize.sh` **nikdy
neběží** → NVP data se nevygenerují, permisse se nesetzují → modul je mrtvý. Buď
přepsat `update-binary` na stock Magisk installer, nebo vždy instalovat přes Magisk app.

### 1.3 Boot lifecycle (co se kdy spustí)
| Fáze | Co se děje | Co zde náš modul dělá |
|---|---|---|
| **install** | ZIP → `$MODPATH` → `/data/adb/modules/<id>` | `customize.sh`: `set_perm` na shelly, `gen_nvp_binary.sh` → `nvp_emulator/nvp_data/` |
| **early boot (post-fs-data)** | `/data` mounted, ještě před `/system`; Magisk už *magic-mountoval* `system/` | `post-fs-data.sh`: permisse, SELinux/permissive, `recreate_symlinks.sh`, mount `/odm`/`/my_product`, `insmod icx_nvp_emmc.ko` (fallback→emulator), IZM HAL fallback, `nvpnode` wrapper |
| **late boot (service.sh)** | `late_start` (non-block), po `sys.boot_completed` | `service.sh`: **resetprop identity + audio-effect property set**, device nodes `/dev/ttymxc*`, `/dev/trusty-ipc-dev0`, restart `audioserver`, start IDD daemon + HAL services, ERRR workaround, final perms |

`service.sh` je **nejdůležitější soubor** — to je, kde Sony/Walkman identity a audio-effect
povolení žijí (všech 40+ `resetprop -n`).

---

## 2. Obsah `module/` — payload inventory (ne binární bloby)

```
module/                            # celý strom je editovatelný, u0_a331
  module.prop                      # metadata Magisk (id=walkman-audio-effects-port)
  Application.mk                   # NDK build spec (arm64-v8a + armeabi-v7a, API 29, c++_static, C++17)
  customize.sh                     # INSTALACE: set_perm + gen NVP data
  post-fs-data.sh                  # EARLY BOOT: permisse, selinux, mount, NVP device, HAL fallback
  service.sh                       # LATE BOOT: resetprop identity/effects, dev nodes, daemons
  function.sh                      # helper utility (mount_partitions, remount, set_read_write, …)
  recreate_symlinks.sh             # znovuvytvoření ztracených symlinků při zipování
  system.prop                      # statické system properties (FSL parsery, ro.sony.audio.*, …)
  package.txt                      # seznam balíčků pro sulist/denylist (Sony Walkman + 2 Android)
  META-INF/com/google/android/
    update-binary                  # STUB `exit 0` (nefunguje přes TWRP!)
    updater-script                 # `1`
  nvp_emulator/                    # ALTERNATIVNÍ toolkit (viz §5) — 8 .sh + README + (gen nvp_data)
    *.sh, README.md
  system/                          # GITIGNORED — flash-time overlay payload (Sony blobs)
```

### 2.1 `system/` payload (gitignored, root-owned, read-only snapshot na zkoušení)
Přesný počet: **259 × `.so`** (verify: `find module/system -name '*.so' -type f | wc -l` = 259).
`lib/` má 35 .so, `lib64/` má 29; zbytek je v `vendor/{lib,lib64}/`. To je *pouze* pro
DT_NEEDED analýzu a node validaci — nikdy flashovat. Obsah (zjištěno):

- **`vendor/lib64/hw/audio.{primary,stub.primary}.msm8996.so`** — Klíč! Přepisuje se OnePluse 3
  nativní primary audio HAL `audio.primary.msm8996.so` za Sony verzi (ICX1295-aware).
  Tím se Walkman efekty a NVP propojí s AOSP audiosubsystemem.
- **`vendor/lib64/hw/audio.primary.icx1295.so`, `audio.a2dp.icx1295.so`,
  `audio.primary.imx8.so`, `audio.stub.imx8.so`** — Sony reference HAL variants.
- **`vendor/lib64/{libizmproperties.so, izm.android.properties@1.0.so, libidd.so,
  libtrusty.so, libprotobuf-c-idd.so, libcodec.so, ...}`** — IZM/NVP + IDD + Trusty + codec.
- **`vendor/bin/hw/{izm.android.properties@1.0-service, vendor.semc.system.idd@1.0-service}`**
  — HAL služby (startuje `service.sh`).
- **APK (priv-app/app)**: `SoundEffectApp`, `IzmAudioManager`, `IzmDeviceManager`,
  `AudioInfoExtractor`, `StorageMonitorService`, `BatteryCtrlService`, `FuncCoreChina`,
  `ReginfoViewApp`, `logdumper`, + AOSP `Provision`/`DefaultContainerService`.
  → package names odpovídají `package.txt` (viz §6).
- **`framework/`**: `com.sonyericsson.idd_impl.jar`, `com.google.protobuf-2.3.0.jar`.
- **`lib/aarch64-linux-gnu/`**: glibc 2.25 loader chain (viz §7).
- **`bin/`**: GNU binárky (`fusermount`, `openssl`, `idds`, `tinycap`, `tinyplay`,
  `ld-2.25.so`, `init_nvp`) + Sony shell tooling (`logcopy.sh`, `optcopy.sh`,
  `precopy.sh`, `start_diag`, `start_initialize`, `tool_early_switcher`, `tool_libs`,
  `tool_switcher`).
- **`etc/`**: `permissions/{privapp-permissions-icx1295.xml, privapp-permissions-izm.xml,
  amb-battery-exceptions.xml, ...}`, `sysconfig/config-*.xml`, `dic/` (Pinyin IME).
- **`vendor/firmware/imx/sdma/sdma-imx7d.bin`** — i.MX SDMA mikrocode (audio DSP FW).

---

## 3. File-by-file reference (kdo co dělá, v které fázi)

| Soubor | Fáze | Role | Klíčové body |
|---|---|---|---|
| `module.prop` | inst/collect | metadata Magisk (id,name,version,code,author,description) | `id=walkman-audio-effects-port` |
| `Application.mk` | build | NDK spec: `APP_ABI arm64-v8a armeabi-v7a`, `android-29`, `c++_static`, `-std=c++17` | pro `src/effect.cpp` build; pro AOSP mmm se ignoruje |
| `customize.sh` | **instalace** | jednorázová instalace | `set_perm` shelly (0755), pak `gen_nvp_binary.sh` → `nvp_emulator/nvp_data/`, verify `000/022/138` |
| `post-fs-data.sh` | **early boot** | permisse + early init | remount `/data` rw, `set_perm_recursive`, SELinux/permissive (`magiskpolicy --live "permissive *"` → **PERSISTENT permissive!**), `recreate_symlinks.sh`, mount `/odm`/`/my_product`, `insmod icx_nvp_emmc.ko` (fallback→gen+cp `/dev/icx_nvp`), IZM HAL fallback (`nohup su system -c … izm.android.properties@1.0-service`), generuje `nvpnode` wrapper |
| `service.sh` | **late boot** | hlavní identity + efekty | **všech 40+ `resetprop -n`** (Sony device identity 0x310000/ZX507 CEW, všechny audio effect enable flagy, volume/AVLS, safe-volume, MTP), device nodes `/dev/ttymxc{0,1,2}` + `/dev/trusty-ipc-dev0`, `killall audioserver`/`audio.service` (reload HAL), IDD daemon + HAL services, ERRR workaround (re-apply identity ve 15s loop), `filezip.sh`, sulist/denylist z `package.txt` |
| `function.sh` | lib (volán z customize/post-fs) | mount helpers | `mount_partitions_in_recovery`, `get_device`, `mount_mirror`, `remount_rw/ro`, `set_read_write` |
| `recreate_symlinks.sh` | early boot | GNU ld/soname symlinky | linky `ld-linux-aarch64.so.1→ld-2.25.so`, `libc.so.6→libc-2.25.so`, `libfuse.so.2→…`, … pro GNU binárky v `bin/` |
| `system.prop` | boot (Magisk append) | statické properties | FSL parsery, `ro.sony.audio.{dsee_ai,clearphase,vinyl,dsx,heq,vpt,drx,360ra}`, `persist.vendor.izmprop.initialized=false`, volume defaults |
| `package.txt` | late boot | sulist/denylist | 9 Walkman balíčků + `com.android.defcontainer` + `com.android.provision` |
| `META-INF/.../update-binary` | — | **stub** `exit 0` | nefunguje přes TWRP! (viz §1.2) |
| `META-INF/.../updater-script` | — | `1` | |
| `nvp_emulator/*.sh` | toolkit (nepojatý) | alternativní emulator | viz §5 |

> `system.prop` je Magisk-injectovaný — Magisk ho přidá do `/system` properties (ať už
> přes `magisk --resetprop` nebo mount). `service.sh` pak přepisuje hodnoty `resetprop -n`
> (runtime), takže `system.prop` slouží jako default před tím, než `service.sh` přebije.

---

## 4. Spouštěcí timeline (fáze → fáze)

```
[INSTALACE]
  customize.sh
    ├─ set_perm: shelly 0755 (gen_nvp_binary, init_nvp, nvp_fuse, service, post-fs-data, recreate_symlinks)
    └─ gen_nvp_binary.sh  → nvp_emulator/nvp_data/{000..242}  (243 × 4-byte LE)
        └─ verify: 000=01.., 022=0x00000103, 138=1

[EARLY BOOT]  (post-fs-data.sh)
  ├─ remount /data rw (mount -o rw,remount /data)
  ├─ set_perm_recursive(MODPATH, 0,0, 0755/0644)
  ├─ SELinux: chmod 0755 libmagiskpolicy.so; magiskpolicy --live "permissive *"; apply sepolicy.pfsd/sepolicy.rule
  │     ⚠️  "permissive *" = **vypíná SELinux enforce globálně** (nejen pro modul)
  ├─ recreate_symlinks.sh  (GNU glibc ld/soname linky)
  ├─ mount_odm / mount_my_product  (pokud není v Magisk mount)
  ├─ insmod icx_nvp_emmc.ko  → /dev/icx_nvp/NNN
  │     └─ FAIL → fallback: gen_nvp_binary + cp /dev/icx_nvp/{000..242}
  ├─ IZM Properties HAL fallback (su system -c … service)
  └─ generuje nvpnode wrapper do $MODDIR/system/vendor/bin

[LATE BOOT]  (service.sh)
  ├─ LOG ROTATE debug.log (512KB)
  ├─ resetprop: ro.sony.volume_limit=0, ro.sony.walkman.euvollimit=0, ... (identity 0x310000/ZX507 CEW)
  │   ├─  ro.effect.*: dsee_ai, clear_phase, vinyl, source_direct, clear_audio_plus,
  │   │  dc_phase_linearizer, dynamic_normalizer, equalizer_10  (všechny = true/enabled)
  │   ├─  ro.{dsee_ai,clear_phase,vinylprocessor}.filepath.* → /vendor/etc/*.bin/.dcfg/.lps/.csv
  │   └─  volume + AVLS + safe-volume + NC ambient + MTP + updater + WiFi identity
  ├─ mknod /dev/ttymxc{0,1,2} c 1 3; /dev/trusty-ipc-dev0  (i.MX UART + Trusty IPC)
  ├─ killall audioserver / audio@4.0-service-mediatek / audio.service   ← reload s novým HAL
  ├─ mkdir /mnt/vendor/idd/{output,socket,startup-prober,private,lost+found} + perms
  ├─ IZM HAL restart (podobně jako post-fs-data, ale později)
  ├─ load_sony_driver / init.insmod.sh  + set vendor.load_nvp_driver.done=1
  ├─ ERRR workaround: 15s loop čeká na `persist.vendor.izmprop.initialized=true` nebo
  │   `init.svc.hw-properties-hal-1-0=stopped`, pak **znovu** resetprop identity (HAL přepisuje)
  ├─ wait sys.boot_completed (≤60s), **znovu** resetprop identity
  ├─ sulist/denylist z package.txt  (magisk --sulist add / magiskhide)
  ├─ nvpnode wrapper (znovu, jindy)
  ├─ final perms (bin 0755/0.2000, bin/hw 0755, xbin)
  ├─ start /vendor/bin/iddd  +  vendor.semc.system.idd@1.0-service
  └─ icx_syslog -n 32 -l 6 -d /mnt/vendor/var   +  filezip.sh
```

> **Pozor na duplikaci:** oba `.sh` (post-fs-data + service) dělají NVP init, IZM HAL start,
> nvpnode wrapper a identity resetprop **dvakrát**. `service.sh` je "autoritativní" (běží dřív
> než audioserver, má ERRR workaround + boot wait). `post-fs-data.sh` verze jsou fallback
> pro early-boot edge cases. Není to bug, ale *redundance* — je to cena "funguj i když
> service.sh pozdě selže".

---

## 5. NVP subsystém — dvě implementace (klíčová analýza)

### 5.1 Co je NVP?
Sony ICX1295 má NVRAM (NVP) partici: 243 nodů × 4 byty. Čte ji `libizmproperties.so`
(`nvp_read`: `cmp w0,#4` — **povinně 4 byty!** viz `gen_nvp_binary.sh` FIX B1)
a Sony appky (`IzmPropertiesHelper.fromByteToInt`: `ByteBuffer.wrap(b).order(LE).getInt()`).
Zařízení: `/dev/icx_nvp/NNN`.

### 5.2 Implementace A — INLINE (aktivní, běží)
- **generování:** `customize.sh` → `gen_nvp_binary.sh` (243 nodů, 4-byte LE, source offset `0x00cbd0`
  z `libizmproperties.so`).
- **publikování do `/dev/icx_nvp/`:** `post-fs-data.sh` (inline, 98–107) a `service.sh` (182–190)
  — `cp $NVP_DATA_DIR/$node /dev/icx_nvp/$node`. (Symlink verze `ln -sf` je zakomentovaná.)
- **Sony tooling:** `service.sh` generuje `$MODDIR/system/vendor/bin/nvpnode` wrapper
  (heredoc 198–338), který ovládá `nvp_emulator.sh`-emulovaná data.
- **Status:** ✅ aktivní, je součástí živého boot chainu.

### 5.3 Implementace B — `nvp_emulator/` (plnější, ALE nezapojená)
8 skriptů (`init_nvp.sh`, `nvp_emulator.sh`, `nvp_wrapper.sh`, `nvp_daemon.sh`,
`setup_nvp_emulator.sh`, `nvp_fuse.sh`, `integrate_with_service.sh`, `gen_nvp_binary.sh`):
- `nvp_emulator.sh` – hlavní: `init/read/write/stat/eraseall` + `/dev/icx_nvp`.
- `nvp_wrapper.sh` – přesměrování `nvpflag/nvpnode/nvpinfo/nvpstr/nvp` na emulator.
- `nvp_daemon.sh` – persistentní daemon `start/stop/status/restart`.
- `nvp_fuse.sh` + `nvp_fuse_helper` (binární, gitignored) – FUSE char-device shim (ioctl).
- `setup_nvp_emulator.sh` – instalace do module dir + wrapper do `$PATH`.
- `integrate_with_service.sh` – *ukázka* (cat-heredoc), jak připojit k service.sh.

### 5.4 Dual implementation — stavy
| | A (inline) | B (emulátor) |
|---|---|---|
| Data gen | `gen_nvp_binary.sh` (v customize + fallback) | `gen_nvp_binary.sh` |
| `/dev/icx_nvp` | `cp` v post-fs-data + service | `nvp_emulator.sh init` (cp) / `nvp_fuse.sh` (FUSE, volitelné) |
| Sony nvp tools | `nvpnode` wrapper (inline heredoc v service.sh) | `nvp_wrapper.sh` (plnotahodnotý dispatch) |
| Daemon | žádný (statické cp) | `nvp_daemon.sh` (persistentní) |
| ioctl/FUSE | ne | ano (nvp_fuse.sh) |
| **Zapojení do bootu** | ✅ ano | ❌ **ne** (nikde nevolán z customize/post-fs-data/service) |

**Verdikt:** `nvp_emulator/` je **paralýza/nepoužito**. Obsahuje lepší tooling (daemon, ioctl/FUSE,
full wrapper dispatch), ale **nikdo ho nevolá** — boot chain používá inlined verze
v `post-fs-data.sh`/`service.sh`. README v `nvp_emulator/` tuto mezeru neuvídí
(říká "automatically installed when flashed" — **lže**, viz gap v §8).

---

## 6. Audio effects — jak to fakt funguje

### 6.1 NENÍ `soundfx/`
`find module/system -path '*soundfx*'` → **empty**. Nikoli žádný
`libeffect.so`/`libdseehandler.so`. Effekty nejsou Android `audio_effect` library,
jsou **zabudované do Sony audio HAL**.

### 6.2 Jak se efekty zapínají (skutečný mechanismus)
1. **`audio.primary.msm8996.so`** (v `module/system/vendor/lib64/hw/`) — nahrazuje OnePlus 3
   nativní HAL za Sony ICX1295-aware verzi. Tím se `audioserver` (spánek 446) spojí s
   ICX1295 efektní pipeline (DSEE AI, ClearPhase, Vinyl, VPT, HEQ, DRX, 360RA, NC Ambient).
2. **Property identity** (`service.sh` resetprop): `ro.sony.deviceimplementationid 0x310000`,
   `vendor.destination 259`, `vendor.model_id 0x310000`, `ro.product.destination 0x3`,
   `ro.effect.<name>.enabled true` — HAL čte tyto property a aktivuje efekty.
3. **Aplikace** (`package.txt`/`priv-app/`): `SoundEffectApp`, `IzmAudioManager`,
   `IzmDeviceManager`, `AudioInfoExtractor`, … — runtime UI + effect config;
   `service.sh` ich přidá do `sulist` (aby viděly modul + `/dev/icx_nvp`).
4. **NVP nodes** (`gen_nvp_binary.sh`): `018`=ModelID, `022`=destination CEW, `138`=DSEE AI enabled,
   `124`=AVLS — `libizmproperties.so` čte z `/dev/icx_nvp`, aby HAL věděl, jaké efekty/nastavit.

### 6.3 Gap: chybějící koeficientní soubory
`service.sh` resetprop nastavuje cesty:
- `/vendor/etc/DseeAi_ICX1295.bin`, `/vendor/etc/DseeAi_ICX1295.dcfg`
- `/vendor/etc/ClearPhase_HP_NW510N_{44100,48000,88200,96000,176400,192000}.lps`
- `/vendor/etc/vinylcoeff.csv`

**Tyto soubory NEJSOU v `module/system/vendor/etc/`** (tam jsou jen `dic/`, `permissions/`,
`sysconfig/`). → Efekty mají nastavit identity/cesty, ale **koeficientní data chybí** →
DSEE/ClearPhase/Vinyl pravděpodobně *neaktivní* nebo padají. Either backport z ICX1295 dump,
build empty stub, nebo symlink na `icx1295/` ROM.

---

## 7. GNU/glibc userspace na Androidu (Bionic) — nejtěžší část

**Neříká se "všechny binárky jsou GNU". Rozdělení je podle `file` + `readelf -l`
(verified 14.8.2026):**

`module/system/bin/` obsahuje 3 kategorie:

1. **Shell skripty** (8): `init_nvp` (sourced `/vendor/usr/data/icx_nvp.cfg`!),
   `logcopy.sh`, `optcopy.sh`, `precopy.sh`, `start_diag`, `start_initialize`,
   `tool_early_switcher`, `tool_libs`, `tool_switcher`.

2. **64-bit aarch64 glibc GNU** (1): jen `fusermount`.
   - INTERP `/system/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`
   - NEEDED `libc.so.6` → `recreate_symlinks.sh` linkne na `libc-2.25.so`.
   - → Toto je jediný binárek, pro který je glibc loader chain nutný.

3. **2 32-bit ARMhf glibc** (0 funguje): `openssl`
   - INTERP `/lib/ld-linux-armhf.so.3` — **32-bit!**
   - NEEDED: `libssl.so, libcrypto.so, libglibc_bridge.so, libc++.so.1, libdl.so.2,
     libc.so.6, ld-linux-armhf.so.3, librt.so.1, libpthread.so.0, libm.so.6, …`
   - ⚠️ **V payloadu neexistuje žádný 32-bit armhf glibc** (`lib/arm-linux-gnueabihf`,
     `ld-linux-armhf.so.3` → nic). `openssl` tedy **nepadne**. Pokud ho opravdu
     potřebuješ (keygen, TLS pro IDD), musíš doplnit 32-bit armhf glibc tree, nebo
     nahradit 64-bit ELF verzí.

4. **64-bit Android/Bionic ELF** (3): `idds`, `tinycap`, `tinyplay`
   - INTERP `/system/bin/linker64`, NEEDED `libcutils/libc++/libbinder/liblog/...`
   - → Native, **žádný glibc není potřeba**; běží přímo.

**`libizmproperties.so`** (NVP reader, zdroj FIX B1) NEEDED = `liblog.so, libc++.so,
libc.so, libm.so, libdl.so` — to jsou **Bionic Sonames** (`/libc.so.6` = glibc;
`/libc.so` = Bionic). → `libizmproperties.so` je **native Android .so**, běží pod
`linker64`, NVP data čte jako běžný vendor lib.

**Závěr:** glibc compat layer (`lib/aarch64-linux-gnu/` + `recreate_symlinks.sh`)
slouží **jen `fusermount`**. `openssl` je broken (32-bit armhf, žádný loader). `idds`/
`tinycap`/`tinyplay` jsou native. `nvp_fuse.sh` (volitelný FUSE NVP) by tedy mohl
padnout kvůli `openssl`, nikoliv kvůli `fusermount`. Navíc `nvp_fuse_helper` (binární,
volaný `nvp_fuse.sh`) je gitignored → `nvp_emulator/` FUSE cesta nikdy nemůže fungovat
z buildnutého ZIPu (chybí helper).

---

## 8. Lairy / nekonzistence / neotřelé otevřené otázky

1. **`update-binary` je stub (`exit 0`).** TWRP flash → `customize.sh` se nespustí → NVP+permisse
   se nenastaví. ✅ Instalovat jen přes Magisk app. (Nebo doplnit stock installer.)
2. **SELinux `permissive *` (post-fs-data.sh:56).** `magiskpolicy --live "permissive *"` dělá
   celý systém permissive, ne jen modul. To je tvoje volba? Pokud ne, nahradit konkrétní
   pravidly pro `u:object_r:system_lib_file:s0` apod.
3. **`nvp_emulator/` nikde nevolán.** Paralýza — lepší toolkit, ale neaktivní.
   Rozhodni: (a) zrušit `nvp_emulator/` a použít inlined, (b) přepojit boot na
   `nvp_emulator` (volání `init`/`nvp_daemon.sh start` z service.sh), (c) odstranit
   duplicitu (dva nvpnode wrappery → jeden).
4. **`nvp_emulator/README.md` je zastaralý.** Říká "9 scriptů" (je jich 8) a node-map
   (000–093) neodpovídá `gen_nvp_binary.sh` (má node 112,137–159,193–215,203–206,…).
   README musí být regenerován z `gen_nvp_binary.sh`.
5. **Chybějící efektní koeficienty** (§6.3): `.bin/.dcfg/.lps/.csv` na `/vendor/etc`
   nejsou v payloadu → DSEE/ClearPhase/Vinyl nebudou plně funkční.
6. **`module/bin/{fusermount,openssl,ldd?}`** — je `fusermount` staticky linkovaný na glibc
   2.25? Potřebuje `readelf -l` overit INTERP + DT_NEEDED. Stejně pro `idds`, `openssl`.
   (To je přesně úloha `add-dlopen-dependency-android-so`.)
8. **`nvp_data/` je vygenerovaný a gitignored** — dobře. Ale `customize.sh` volá
   `gen_nvp_binary.sh` i `post-fs-data.sh`/`service.sh` mají fallback generate. Trik:
   `nvp_fuse_helper` (binární) v `nvp_emulator/` je gitignored → není ve zdroji →
   kdokoliv buildne ZIP z `module/`, nebude mít fusku helper. Je to jen v dev prostředí.
9. **`bin/openssl` je 32-bit ARMhf glibc** (INTERP `/lib/ld-linux-armhf.so.3`); payload
   neobsahuje 32-bit armhf libc → **openssl lze spustit jen s doplnitkem armhf tree**.
   Ověřit `file`/`readelf -l` na device před použitím.
10. **`bin/init_nvp` je shell script**, který sourcuje `/vendor/usr/data/icx_nvp.cfg`.
    Ten config **není v payloadu** (`vendor/usr/*` jsou prázdné stuby) → `init_nvp` selže
    (sh `. nonexistent` = exit 1, ale nikdo neví). Ověřit, zda `init_nvp` vůbec někdo volá.
8. **ERRR workaround (service.sh:393-415).** Loop čeká na `persist.vendor.izmprop.initialized=true`.
   Pokud HAL nikdy nenastartuje (neSony HW), loop dojede do 15s a pokračuje. OK, ale
   `resetprop -p --delete` na `persist.vendor.audio.mixerthread.res` + `std` přepis
   může chovat podivně; ověřit v logcatu.

---

## 9. Rychlý referenční index (orientační tabulka)

| Co hledám | Kde |
|---|---|
| Metadata modulu | `module/module.prop` |
| Co se dělá při instalaci | `module/customize.sh` |
| Co se dělá hned po botu | `module/post-fs-data.sh` |
| Hlavní identity + audio efekty | `module/service.sh` (resetprop sekce 49–180) |
| GNU/glibc loader linky | `module/recreate_symlinks.sh` |
| Seznam balíčků pro sulist | `module/package.txt` |
| Statické system properties | `module/system.prop` |
| NDK build spec | `module/Application.mk` |
| NVP data → výchozí hodnoty | `module/nvp_emulator/gen_nvp_binary.sh` |
| NVP device nodes → /dev/icx_nvp | inline v `post-fs-data.sh`+`service.sh` (cp fallback) |
| Sony proprietární HAL/lib | `module/system/` (gitignored, read-only) |
| Walkman audio HAL (hlavní) | `module/system/vendor/lib64/hw/audio.primary.msm8996.so` (není v git, root-owned) |
| IZM/NVP property reader | `module/system/vendor/lib64/libizmproperties.so` (FIX B1 zdroj) |
| HAL služby | `module/system/vendor/bin/hw/izm.android.properties@1.0-service`, `vendor.semc.system.idd@1.0-service` |
| GNU binárky (fusermount/openssl/idds) | `module/system/bin/` |
| glic loader chain | `module/system/lib/aarch64-linux-gnu/` |
| IDD/A2DP HAL | `module/system/vendor/lib64/hw/audio.a2dp.icx1295.so` |
| Alternativní NVP toolkit | `module/nvp_emulator/` (nepojatý — viz §5.4) |
| Magisk env helpery (mount, remount) | `module/function.sh` |
