# Walkman Audio Effects Port — Magisk Module Architecture

**Scope:** deep analysis of the live Magisk module in `module/`. Answering: *how does this module
actually work on Android 11 / OnePlus 3 (msm8996), file-by-file and lifecycle-by-lifecycle.*

> Note on sources: external dokumentace (topjohnwu/Magisk `docs/modules.md`, `magisk.danty.in`)
> byla nedostupní (404 / DNS). Magisk konstrukce je zde použita jako **navodňený model**
> (verzně stabilní od Magisk 23 do 28) a **podložená konkrétním obsahem** každého skriptu
> v `module/`. Každý technický výrok má odkaz na konkrétní soubor+konkretňák.
>
> **Verifikační pravidlo:** všechny fakty níže jsou *potvrzeny terminálem* (`ls -la`, `readelf -d`,
> `grep`), ne dedukované. `readelf`/`nm` strukturně OK ≠ runtime OK — skutečný test je device + logcat.

---

## 0. Orientace (rychlý tah)

- **`module/` = jedinná source of truth** pro build. `module/system/` uvnitř je **gitignored**
  (viz `.gitignore` koře) — je to *flash-time payload* (Sony proprietární binárky), ne source.
  Nesnaž se ho "upravovat jako source". Používej ho jen read-only jako referenční snapshot.
- **Tři fáze životnosti modulu:** `customize.sh` (instalace, jednorázově) →
  `post-fs-data.sh` (brzy po bootu) → `service.sh` (později po bootu).
- **Dvě NVP implementace** (viz §5): inline v `post-fs-data.sh`/`service.sh` (aktivní, běží)
  a `module/nvp_emulator/` (plnější toolkit, **nikdy nevolán** z boot chainu → mrtvý).
- **Audio effects se netapí přes `soundfx/`** (adresář prázdný — viz §6.1). Zapínají se přes
  modifikovaný `audio.primary.msm8996.so` (shim s injectovaným `DT_NEEDED`) + sadu resetprop + Sony APK.
- **HLAVNÍ HAL není `msm8996`** — viz §2.1/§6.2. Na OP3 se podle HW názvu načte
  `audio.primary.msm8996.so` (420 KB), který má `DT_NEEDED: /vendor/lib/hw/audio.primary.icx1295.so`
  jako PRVNÍ záznam → deleguje na 2,7 MB `audio.primary.icx1295.so` (skutečný ICX1295 effect pipeline).
  Přesně tento pattern řeší skill `add-dlopen-dependency-android-so`.
- **GNU/glibc userspace na Bionicu** (viz §7): `bin/{fusermount,openssl,idds,...}` +
  `lib/aarch64-linux-gnu/{libc-2.25.so,...}` + `recreate_symlinks.sh`. To je nejtěžší část portu.
- **Všechny efektní koeficienty EXISTUJÍ v payloadu** (`vendor/etc/`) — viz §6.3. §6.3 "Gap"
  v předchozí verzi tohoto doku byl **falešný** (potvrzeno `ls vendor/etc/`).

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
`updater-script` je jen `1` (verify: `cat module/META-INF/.../update-binary`).

→ Modul **není určen na flash přes TWRP**. Instalace proběhne přes Magisk app /
`magisk install-module`, která **ignoruje** tento stub a použije svůj vlastní installer,
který **skutečně** spustí `customize.sh` + nastaví `set_perm`. Všechny instalační
věci (gen NVP, permisse) žijí v `customize.sh`, ne v `update-binary`.

**Pitfall:** Pokud někdo flashne ZIP přes TWRP s tímto stubem, `customize.sh` **nikdy
neběží** → NVP data se nevygenerují, permisse se nesetzují → modul je mrtvý. Buď
přepsat `update-binary` na stock Magisk installer, nebo vždy instalovat přes Magisk app.

### 1.3 Boot lifecycle (co se kdy spustí)
| Fáze | Co se děje | Co zde náš modul dělá |
|---|---|---|
| **install** | ZIP → `$MODPATH` → `/data/adb/modules/<id>` | `customize.sh`: `set_perm` shelly (0755), `gen_nvp_binary.sh` → `nvp_emulator/nvp_data/` |
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
  function.sh                      # helper utility (mount, remount, set_read_write) — **NEVOLÁN (mrtý)**
  recreate_symlinks.sh             # znovuvytvoření ztracených symlinků při zipování
  system.prop                      # statické system properties (FSL parsery, ro.sony.audio.*, …)
  package.txt                      # seznam balíčků pro sulist/denylist (Sony Walkman + 2 Android)
  META-INF/com/google/android/
    update-binary                  # STUB `exit 0` (nefunguje přes TWRP! viz §1.2)
    updater-script                 # `1`
  nvp_emulator/                    # alternativní toolkit (viz §5) — 8 .sh + README + helper
    gen_nvp_binary.sh              # AKTIVNÍ (volán z customize.sh + service.sh fallback)
    init_nvp.sh                    # mrtý (set_perm chmod, nikdy exec)
    nvp_emulator.sh                # mrtý
    nvp_wrapper.sh                 # mrtý
    nvp_daemon.sh                  # mrtý
    setup_nvp_emulator.sh          # mrtý
    nvp_fuse.sh                    # mrtý
    integrate_with_service.sh      # mrtý (jen ukázka cat-heredoc)
    nvp_fuse_helper                # mrtý binární (gitignored)
    nvp_data/                      # GENEROVANÉ (gitignored)
  system/                          # GITIGNORED — flash-time overlay payload (Sony blobs, read-only)
```

> `function.sh` je **mrtý kód** — grep potvrdil, že `customize.sh`/`post-fs-data.sh`/`service.sh`
> ho nikdy `source` nedělají. Obsahuje `mount_partitions_in_recovery`, `get_device`, `mount_mirror`,
> `remount_rw/ro`, `set_read_write`, ale nikdo ho nevolá. Můžeš klidně odstranit.
>
> `system.prop` je Magisk-injectovaný — Magisk ho přidá do `/system` properties (ať už
> přes `magisk --resetprop` nebo mount). `service.sh` pak přepisuje hodnoty `resetprop -n`
> (runtime), takže `system.prop` slouží jako default před tím, než `service.sh` přebije.

### 2.1 `system/` payload (gitignored, root-owned, read-only snapshot na zkoušení)
Přesný počet: **259 × `.so`** (verify: `find module/system -name '*.so' -type f | wc -l` = 259 —
pozn. `module/system` je symlink na `icx1295` ROM-clone; v absolute path se může zdát "neexistuje",
relativně od cwd `module/system` ale vše funguje). `lib/` má 35 .so, `lib64/` má 29; zbytek je v
`vendor/{lib,lib64}/`. To je *pouze* pro DT_NEEDED analýzu a node validaci — nikdy flashovat.

**HLAVNÍ HAL model (odchylka od předchozí verze — potvrzeno `readelf -d`):**

Na OnePlus 3 HW název = `msm8996` → Android linker požaduje `audio.primary.msm8996.so`.
Tenhle soubor je **Sony modifikace** — **shim** (injectovaný `DT_NEEDED` jako první record):
- 64-bit `vendor/lib64/hw/audio.primary.msm8996.so` (420 KB): první `DT_NEEDED` je
  **absolutní cesta** `/vendor/lib64/hw/audio.primary.icx1295.so` (verify `readelf -d`).
- 32-bit `vendor/lib/hw/audio.primary.msm8996.so` (371 KB): první `DT_NEEDED` je
  `/vendor/lib/hw/audio.primary.icx1295.so`.

⚠️ ** historický bug (FIX `2b50c48`+):** původní patchelf injectoval 64-bit shim s 32-bit
cestou `/vendor/lib/hw/...` → 64-bit `linker64` by odmítl `dlopen` icx1295 (ELF class mismatch).
Opraveno na `/vendor/lib64/hw/...`. Verify oba:
`readelf -d lib64/hw/audio.primary.msm8996.so | grep NEEDED` i `readelf -d lib/hw/...`.

```
  NEEDED: [/vendor/lib64/hw/audio.primary.icx1295.so]   ← injectované (patchelf, arch-match)
  NEEDED: liblog.so] libcutils.so] libtinyalsa.so] libhardware.so] libtinycompress.so] libaudioroute.so] libaudioutils.so] libexpat.so] libhidlbase.so] libprocessgroup.so] libc++.so] libc.so] libm.so] libdl.so]
  SONAME: audio.primary.msm8996.so
  FLAGS: BIND_NOW, FLAGS_1: NOW
```

→ `audio.primary.msm8996.so` je **shim/entrypoint**: systém ho načte podle HW názvu, ale jeho
jediným smyslem je `dlopen`ovat (pomocí injectovaného `DT_NEEDED` jako první záznam —
`patchelf --add-needed` prependne) 2,7 MB **`audio.primary.icx1295.so`** (= `vendor/lib64/hw/`
2728960 B, i 32-bit `vendor/lib/hw/` 2390608 B). Ten větší .so je **skutečná Sony ICX1295 HAL**
s plným effect pipeline (DSEE AI / ClearPhase / Vinyl / VPT / HEQ / DRX / 360RA / NC Ambient) +
NVP přes `libizmproperties.so`. Shim dodává QCOM plumbing (`libtinyalsa`, `libaudioroute`,
`libhidlbase` …); icx1295 dodává efekty.

→ Tento `DT_NEEDED`-shim je **právě** pattern ze skillu `add-dlopen-dependency-android-so`
(absolutní cesta do `hw/` podadresáře; bare-name by nezvládl).

Obsah HAL dirů (verify `ls -la`):
- `vendor/lib64/hw/`: `audio.primary.icx1295.so` (2.7 MB, **hlavní**), `audio.a2dp.icx1295.so` (1.9 MB),
  `audio.primary.imx8.so` (77 KB), `audio.stub.imx8.so` (77 KB), `audio.primary.msm8996.so` (420 KB, shim).
- `vendor/lib/hw/` (32-bit): stejné 4 + `sound_trigger.primary.default.so`.
- `lib64/hw/` i `lib/hw/` (ne-vendor) **neexistují** — všechny HALy jsou pod `vendor/`.

- **`audio.primary.icx1295.so` (2,7 MB) NEEDED:** `liblog.so`, `libcutils.so`, `libtinyalsa.so`,
  `libasound.so`, `izm.android.properties@1.0.so`, `libhardware.so`, `libhidlbase.so`,
  `libhidltransport.so`, `libutils.so`, `libc++.so`, `libc.so`, `libm.so`, `libdl.so` (všechno Bionic,
  `FLAGS: BIND_NOW`).
- ⚠️ **`TEXTREL` — potvrzené `readelf -d`:** `icx1295.so` má
  `(TEXTREL) 0x0` + `FLAGS: TEXTREL BIND_NOW` + `FLAGS_1: NOW`. Na Android 11 (Bionic linker) je
  TEXTREL **riskem** — linker může odmítnout `dlopen` při `dlopen` v režimu `RTLD_NOW`. Je to
  64-bit `libcxx`+`asm` runtime fixups (rehost/PLT). Dokud `dlopen` selže, AUDIO HAL se nepodaří
  načíst → fallback k `audio.primary.default.so` → **žádné efekty**. Viz §8 (TEXTREL mitigation TODO).
  `msm8996.so` (shim) **nemá** TEXTREL — jen `FLAGS: BIND_NOW`, takže selhání pochází z icx1295.
- **`izm.android.properties@1.0.so` NEEDED:** `libhidlbase`, `libhidltransport`, `libhwbinder` (nebo
  `libhwbinder` na starém), `liblog`, `libutils`, `libcutils`, `libc++`, `libc`, `libm`, `libdl` —
  HIDL binder shim mezi HAL a `libizmproperties.so`.
- **`libizmproperties.so`** (NVP reader, zdroj FIX B1): NEEDED `liblog.so`, `libc++.so`,
  `libc.so`, `libm.so`, `libdl.so` (Bionic sonames; `/libc.so.6` = glibc, `/libc.so` = Bionic →
  tohle je nativní Android .so pod `linker64`, NVP data čte jako běžný vendor lib).

### 2.2 Balíčky / služby
- **`vendor/bin/hw/{izm.android.properties@1.0-service, vendor.semc.system.idd@1.0-service}`** —
  HAL služby (startuje `service.sh`).
- **`framework/`**: `com.sonicernericsson.idd_impl.jar`, `com.google.protobuf-2.3.0.jar`.
- **`bin/`** (3 kategorie dle `file`+`readelf -l`):
  1. **Shell skripty (9):** `init_nvp` (sourced nikdy-volaný `/vendor/usr/data/icx_nvp.cfg`),
     `logcopy.sh`, `optcopy.sh`, `precopy.sh`, `start_diag`, `start_initialize`,
     `tool_early_switcher`, `tool_libs`, `tool_switcher` — všechny **Sony factory tooling,
     nikdo je nevolá** (viz §8).
  2. **64-bit aarch64 glibc GNU (1):** jen `fusermount` — INTERP
     `/system/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`, NEEDED `libc.so.6` →
     `recreate_symlinks.sh` linkne na `libc-2.25.so`. Je jediným binárkem, pro který je
     glibc loader chain nutný.
  3. **64-bit aarch64 Bionic ELF (3):** `idds`, `tinycap`, `tinyplay` — INTERP
     `/system/bin/linker64`, NEEDED `libcutils/libc++/libbinder/liblog/…`. Native,
     **žádný glibc není potřeba**.
- **`module/system/bin/openssl`** (32-bit ARMhf glibc — **BROKEN**): INTERP
  `/lib/ld-linux-armhf.so.3`, NEEDED `libssl.so.1.1`, `libcrypto.so.1.1`, `libglibc_bridge.so`,
  `libc++.so.1`, `libdl.so.2`, `libc.so.6`, `librt.so.1`, `libpthread.so.0`, `libm.so.6`, …
  → payload neobsahuje 32-bit armhf glibc (`lib/arm-linux-gnueabihf`, `ld-linux-armhf.so.3` → nic).
  `openssl` tedy **nepadne**. Nahradit 64-bit ELF verzí nebo doplnit armhf strom.
- **`lib/aarch64-linux-gnu/`**: jen 8 glibc `.so` (podporuje jen `fusermount`).
- **`etc/`**: `permissions/{privapp-permissions-icx1295.xml, privapp-permissions-izm.xml,
  amb-battery-exceptions.xml, …}`, `dic/` (Pinyin IME), `sysconfig/config-*.xml`.
- **`vendor/firmware/imx/sdma/sdma-imx7d.bin`** — i.MX SDMA mikrocode (audio DSP FW).

---

## 3. File-by-file reference (kdo co dělá, v které fázi)

| Soubor | Fáze | Role | Klíčové body |
|---|---|---|---|
| `module.prop` | inst/collect | metadata Magisk (id,name,version,code,author,description) | `id=walkman-audio-effects-port` |
| `Application.mk` | build | NDK spec: `APP_ABI arm64-v8a armeabi-v7a`, `android-29`, `c++_static`, `-std=c++17` | pro `src/effect.cpp` build; pro AOSP mmm se ignoruje |
| `customize.sh` | **instalace** | jednorázová instalace | `set_perm` shelly (0755) i na `nvp_emulator/init_nvp.sh`+`nvp_fuse.sh`; pak `mkdir nvp_data` → `sh gen_nvp_binary.sh nvp_data`; verify nodů 000/022/138 |
| `post-fs-data.sh` | **early boot** | permisse + early init | remount `/data` rw, `set_perm_recursive`, SELinux/permissive (`magiskpolicy --live "permissive *"` → **global permissive!**), `recreate_symlinks.sh`, mount `/odm`/`/my_product`, `insmod icx_nvp_emmc.ko` (fallback→gen+cp `/dev/icx_nvp`), IZM HAL fallback, generuje `nvpnode` wrapper |
| `service.sh` | **late boot** | hlavní identity + efekty | **všech 40+ `resetprop -n`** (Sony device identity 0x310000/ZX507 CEW, všechny audio effect enable flagy, volume/AVLS, safe-volume, MTP), device nodes `/dev/ttymxc{0,1,2}` + `/dev/trusty-ipc-dev0`, `killall audioserver`/`audio@4.0-service-mediatek`/`audio.service` (reload HAL), IDD daemon + HAL services, ERRR workaround, final perms |
| `function.sh` | lib | **NEVOLÁN → mrtý** | `grep function.sh module/*.sh` = prázdný výstup. Obsahuje mount/reboot helpery, ale source nikdy. Odstranit nebo nechat mrtvé. |
| `recreate_symlinks.sh` | early boot | GNU/glibc ld+soname linky | linky `ld-linux-aarch64.so.1→ld-2.25.so`, `libc.so.6→libc-2.25.so`, `libfuse.so.2→…`, pro GNU binárky v `bin/` |
| `system.prop` | boot (Magisk append) | statické properties | FSL parsery, `ro.sony.audio.{dsee_ai,clearphase,vinyl,dsx,heq,vpt,drx,360ra}`, `persist.vendor.izmprop.initialized=false`, volume defaults |
| `package.txt` | late boot | sulist/denylist | 9 Walkman balíčků + `com.android.defcontainer` + `com.android.provision` |
| `META-INF/.../update-binary` | — | **stub** `exit 0` | nefunguje přes TWRP! (viz §1.2) |
| `META-INF/.../updater-script` | — | `1` | |

---

## 4. Spouštěcí timeline (fáze → fáze)

```
[INSTALACE]
  customize.sh
    ├─ set_perm: shelly 0755 (gen_nvp_binary, init_nvp, nvp_fuse — ALE init_nvp/nvp_fuse nikdy nespouštěny)
    └─ gen_nvp_binary.sh  → nvp_emulator/nvp_data/{000..242}  (243 × 4-byte LE)
        └─ verify: 000=01.., 022=0x00000103, 138=1

[EARLY BOOT]  (post-fs-data.sh)
  ├─ remount /data rw (mount -o rw,remount /data)
  ├─ set_perm_recursive(MODPATH, 0,0, 0755/0644)
  ├─ SELinux: chmod 0755 libmagiskpolicy.so; magiskpolicy --live "permissive *"
  │     ⚠️  "permissive *" = **vypíná SELinux enforce globálně** (nejen pro modul)
  ├─ recreate_symlinks.sh  (GNU glibc ld/soname linky)
  ├─ mount_odm / mount_my_product
  ├─ insmod icx_nvp_emmc.ko  → /dev/icx_nvp/NNN
  │     └─ FAIL → fallback: gen_nvp_binary + cp /dev/icx_nvp/{000..242}  (service.sh má stejný fallback)
  ├─ IZM Properties HAL fallback (su system -c … izm.android.properties@1.0-service)
  └─ generuje nvpnode wrapper do $MODDIR/system/vendor/bin

[LATE BOOT]  (service.sh)
  ├─ LOG ROTATE debug.log (512KB)
  ├─ resetprop: ro.sony.volume_limit=0, ro.sony.walkman.euvollimit=0, ... (identity 0x310000/ZX507 CEW)
  │   ├─  ro.effect.*: dsee_ai, clear_phase, vinyl, source_direct, clear_audio_plus,
  │   │  dc_phase_linearizer, dynamic_normalizer, equalizer_10  (všechny = true/enabled)
  │   ├─  ro.{dsee_ai,clear_phase,vinylprocessor}.filepath.* → /vendor/etc/*.bin/.dcfg/.lps/.csv
  │   └─  volume + AVLS + safe-volume + NC ambient + MTP + updater + WiFi identity
  ├─ mknod /dev/ttymxc{0,1,2} c 1 3; /dev/trusty-ipc-dev0
  ├─ killall audioserver / audio@4.0-service-mediatek / audio.service   ← reload s novým HAL
  ├─ mkdir /mnt/vendor/idd/{output,socket,startup-prober,private,lost+found} + perms
  ├─ IZM HAL restart (podobně jako post-fs-data, ale později)
  ├─ load_sony_driver / init.insmod.sh  + set vendor.load_nvp_driver.done=1
  ├─ ERRR workaround: 15s loop čeká na persist.vendor.izmprop.initialized=true nebo
  │   init.svc.hw-properties-hal-1-0=stopped, pak **znovu** resetprop identity (HAL přepisuje)
  ├─ wait sys.boot_completed (≤60s), **znovu** resetprop identity
  ├─ sulist/denylist z package.txt
  ├─ nvpnode wrapper (znovu, jindy)
  ├─ final perms (bin 0755/0.2000, bin/hw 0755, xbin)
  ├─ start /vendor/bin/iddd  +  vendor.semc.system.idd@1.0-service
  └─ icx_syslog -n 32 -l 6 -d /mnt/vendor/var   +  filezip.sh
```

> **Duplikace NVP init:** oba `.sh` dělají NVP init, IZM HAL start, nvpnode wrapper a identity
> resetprop **dvakrát**. `service.sh` je "autoritativní" (běží dřív než audioserver, má ERRR
> workaround + boot wait). `post-fs-data.sh` verze jsou fallback pro early-boot edge cases.
> Není to bug — je to cena "funguj i když service.sh pozdě selže".

---

## 5. NVP subsystém — dvě implementace (klíčová analýza)

### 5.1 Co je NVP?
Sony ICX1295 má NVRAM (NVP) partici: **243 nodů × 4 byty** (verify: `gen_nvp_binary.sh`
generuje 000–242; `nvp_data/` má 243 souborů). Čte ji `libizmproperties.so`
(`nvp_read`: `cmp w0,#4` — **povinně 4 byty!** viz `gen_nvp_binary.sh` FIX B1).
Zařízení: `/dev/icx_nvp/NNN`. Sony appky (`IzmPropertiesHelper.fromByteToInt`:
`ByteBuffer.wrap(b).order(LE).getInt()`) čtou stejně.

### 5.2 Implementace A — INLINE (aktivní, běží)
- **generování:** `customize.sh` → `gen_nvp_binary.sh` (243 nodů, 4-byte LE, source offset `0x00cbd0`
  z `libizmproperties.so`). Toto je **jediný** skript z `nvp_emulator/` který se spouští.
- **publikování do `/dev/icx_nvp/`:** `post-fs-data.sh` (inline, 98–107) a `service.sh` (182–190)
  — `cp $NVP_DATA_DIR/$node /dev/icx_nvp/$node`. (Symlink verze `ln -sf` je zakomentovaná.)
- **Sony tooling:** `service.sh` generuje `$MODDIR/system/vendor/bin/nvpnode` wrapper
  (heredoc 198–338), který ovládá inlined NVP data.
- **Status:** ✅ aktivní, součástí živého boot chainu (customize.sh + oba .sh fallbackem).

### 5.3 Implementace B — `nvp_emulator/` toolkit (Aktivní JEN gen_nvp_binary.sh)
8 skriptů v `module/nvp_emulator/`: `gen_nvp_binary.sh`, `init_nvp.sh`, `nvp_emulator.sh`,
`nvp_wrapper.sh`, `nvp_daemon.sh`, `setup_nvp_emulator.sh`, `nvp_fuse.sh`,
`integrate_with_service.sh` + binární `nvp_fuse_helper` (gitignored).
- `gen_nvp_binary.sh` — ✅ volán z `customize.sh:18` + `service.sh:237` (fallback).
- `nvp_emulator.sh`, `nvp_wrapper.sh`, `nvp_daemon.sh`, `nvp_fuse.sh`, `setup_nvp_emulator.sh`,
  `integrate_with_service.sh`, `init_nvp.sh` — ❌ **nikde nevolány** (verify `grep -rn`
  na customize/post-fs-data/service = jen `gen_nvp_binary.sh` + `set_perm` na `init_nvp.sh`/`nvp_fuse.sh`,
  které dostanou chmod ale **nikdy exec**).
- `bin/init_nvp`, `bin/start_initialize`, `bin/start_diag`, `bin/tool_*` — Sony factory tooling
  (eMMC kapacita, `mkfs.ext4 /data`, `reboot`, `lcdmsg`); nikdo nevolá → ignorovat.

### 5.4 Dual implementation — stav
| | A (inline) | B (emulátor toolkit) |
|---|---|---|
| Data gen | `gen_nvp_binary.sh` (customize + service fallback) | `gen_nvp_binary.sh` (stejný soubor) |
| `/dev/icx_nvp` | `cp` v post-fs-data + service | `nvp_emulator.sh init` (cp) / `nvp_fuse.sh` (FUSE, volitelné) |
| Sony nvp tools | `nvpnode` wrapper (inline heredoc v service.sh) | `nvp_wrapper.sh` (plnotahodnotý dispatch) |
| Daemon | žádný (statické cp) | `nvp_daemon.sh` (persistentní) |
| ioctl/FUSE | ne | ano (nvp_fuse.sh + nvp_fuse_helper) — helper **gitignored** |
| **Zapojení do bootu** | ✅ ano | ❌ **ne** (nikde nevolán z customize/post-fs-data/service) |

**Verdikt:** `nvp_emulator/` toolkit je **paralýza/nepoužito**. Obsahuje lepší tooling (daemon,
ioctl/FUSE, full wrapper dispatch), ale **nikdo ho nevolá** — boot chain používá inlined verze
v `post-fs-data.sh`/`service.sh`. Rozhodni: (a) zrušit `nvp_emulator/` a použít inlined,
(b) přepojit boot na `nvp_emulator` (volání `init`/`nvp_daemon.sh start` z service.sh),
(c) odstranit duplicitu (dva nvpnode wrappery → jeden). Dokumentace `nvp_emulator/README.md`
tuto mezeru nelidským způsobem nezdůrazňuje (říká "automatically installed when flashed" — **lže**).

---

## 6. Audio effects — jak to fakt funguje

### 6.1 NENÍ `soundfx/`
`find module/system -path '*soundfx*'` → **empty**. Nikoli žádný `libeffect.so`/`libdseehandler.so`.
Effekty nejsou Android `audio_effect` library; jsou **zabudované do Sony audio HAL**
(`audio.primary.icx1295.so`).

### 6.2 Jak se efekty zapínají (skutečný mechanismus)
1. **Entry HAL `audio.primary.msm8996.so`** (420 KB, `vendor/lib64/hw/`, i 32-bit v `vendor/lib/hw/`)
   — OnePlus 3 ho načte podle HW názvu `msm8996`. Jeho **první `DT_NEEDED`** je absolutní cesta
   `/vendor/lib/hw/audio.primary.icx1295.so` (injectované přes `patchelf --add-needed`,
   viz skill `add-dlopen-dependency-android-so`). Linker tedy `dlopen`ne icx1295 `.so` **před**
   vlastním kódem shimu (prepend → resolve left-to-right). Shim pak poskytuje QCOM plumbing
   (`libtinyalsa`, `libaudioroute`, `libtinycompress`, `libhidlbase`, …).
2. **Delegate HAL `audio.primary.icx1295.so`** (2,7 MB) — načtený jako první závislost. Obsahuje
   kompletní Sony ICX1295 efektní pipeline: DSEE AI, ClearPhase, Vinyl, VPT, HEQ, DRX, 360RA,
   NC Ambient (+ NVP přes `libizmproperties.so` ↔ `izm.android.properties@1.0.so` ↔ `/dev/icx_nvp`).
3. **Property identity** (`service.sh` resetprop, 40+ volání): `ro.sony.deviceimplementationid 0x310000`,
   `vendor.destination 259`, `vendor.model_id 0x310000`, `ro.product.destination 0x3`,
   `ro.effect.<name>.enabled true` — HAL čte tyto property a aktivuje efekty.
4. **Aplikace** (`package.txt`/`priv-app/`): `SoundEffectApp`, `IzmAudioManager`,
   `IzmDeviceManager`, `AudioInfoExtractor`, `StorageMonitorService`, `BatteryCtrlService`,
   `FuncCoreChina`, `ReginfoViewApp`, `logdumper`, + AOSP `Provision`/`DefaultContainerService`.
   `service.sh` přidáva do `sulist` (aby viděly modul + `/dev/icx_nvp`).
5. **NVP nodes** (`gen_nvp_binary.sh`): `000`=verze(1), `018`=ModelID(`0x31000000` ZX507 CEW),
   `019`=Serial, `022`=Destination(`0x00000103` CEW), `033`=BT initflag, `124`=AVLS, `138`=DSEE AI,
   `174`=DSEE HXL on — `libizmproperties.so` čte z `/dev/icx_nvp`, aby HAL věděl efekty/nastavení.

### 6.3 Koeficientní soubory — KOMPLETNÍ v payloadu (potvrzeno `ls vendor/etc/`)
Všechny koeficientní údaje, na které `service.sh` odkazuje `ro.*.filepath.*`, **existují**
v `module/system/vendor/etc/`:

| Efekt | Soubor(y) | Velikost |
|---|---|---|
| DSEE AI | `DseeAi_ICX1295.bin` + `DseeAi_ICX1295.dcfg` | 60000 / 20 B |
| DSEE AI (older ICX1293) | `DseeAi_ICX1293.bin` + `DseeAi_ICX1293.dcfg` | 60000 / 20 B |
| ClearPhase HP | `ClearPhase_HP_NW510N_{44100,48000,88200,96000,176400,192000}.lps` (6) | 8356–32932 B |
| ClearPhase HP | `ClearPhase_HP_NW500N_{44100,48000,88200,96000,176400,192000}.lps` (6) | 8356–32932 B |
| Vinyl | `vinylcoeff.csv` | 173515 B |
| SoundBooster | `SoundBoosterParam.txt` (+ `vendor/firmware/SoundBoosterParam.bin`) | 23088 / 16240 B |
| Drangepara AAC | `DrangeparaAAC{64,128,256}.bin` (3) | 426576 B |
| Drangepara MP3 | `DrangeparaMP3_{128,160,192}.bin` (3) | 426576 B |
| Policy | `audio_policy_configuration.xml`, `audio_policy_configuration_highres.xml`, `stub_audio_policy*.xml` | 23837 / 24977 / … B |

→ **Neexistuje žádný gap.** §6.3 "chybějící koeficienty" v předchozí verzi doku byl **falešný**.
Akty se nedostanou efekty jen kvůli chybějícím souborům — příčina problemu (kdybýval) je jinde
(SELinux, property overwrite, HAL selhání na bootu, nebo `permissive *`).

---

## 7. GNU/glibc userspace na Androidu (Bionic) — nejtěžší část

**Neříká se "všechny binárky jsou GNU".** Rozdělení dle `file` + `readelf -l`
(verified 14.8.2026):

`module/system/bin/` obsahuje 3 kategorie:

1. **Shell skripty (9):** `init_nvp` (sourced `/vendor/usr/data/icx_nvp.cfg!` — config **neexistuje**),
   `logcopy.sh`, `optcopy.sh`, `precopy.sh`, `start_diag`, `start_initialize`,
   `tool_early_switcher`, `tool_libs`, `tool_switcher`. Všechny Sony factory tooling, nikdo nevolá.
2. **64-bit aarch64 glibc GNU (1):** jen `fusermount`. INTERP
   `/system/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`, NEEDED `libc.so.6` →
   `recreate_symlinks.sh` linkne na `libc-2.25.so`. Je jediným binárkem, pro který je glibc loader chain nutný.
3. **64-bit aarch64 Bionic ELF (3):** `idds`, `tinycap`, `tinyplay` — INTERP
   `/system/bin/linker64`, NEEDED `libcutils/libc++/libbinder/liblog/…`. Native,
   **žádný glibc není potřeba**; běží přímo.

`module/system/bin/openssl` — **32-bit ARMhf glibc (BROKEN)**: INTERP `/lib/ld-linux-armhf.so.3`,
NEEDED `libssl.so.1.1`, `libcrypto.so.1.1`, `libglibc_bridge.so`, `libc++.so.1`, `libdl.so.2`,
`libc.so.6`, `libpthread.so.0`, `libm.so.6`, `librt.so.1`, …
→ payload neobsahuje 32-bit armhf glibc (`lib/arm-linux-gnueabihf`, `ld-linux-armhf.so.3` → nic).
`openssl` tedy **nepadne**. Pokud ho opravdu potřebuješ (keygen, TLS pro IDD), musíš doplnit
32-bit armhf glibc tree, nebo nahradit 64-bit ELF verzí.

`module/system/lib/aarch64-linux-gnu/` má jen 8 glibc `.so` — podporuje jen `fusermount`.

**`libizmproperties.so`** (NVP reader, zdroj FIX B1) NEEDED = `liblog.so`, `libc++.so`,
`libc.so`, `libm.so`, `libdl.so` — to jsou **Bionic Sonames** (`/libc.so.6` = glibc;
`/libc.so` = Bionic). → `libizmproperties.so` je **native Android .so**, běží pod
`linker64`, NVP data čte jako běžný vendor lib.

**Závěr:** glibc compat layer (`lib/aarch64-linux-gnu/` + `recreate_symlinks.sh`)
slouží **jen `fusermount`**. `openssl` je broken (32-bit armhf, žádný loader). `idds`/`tinycap`/
`tinyplay` jsou native. `nvp_fuse.sh` (volitelný FUSE NVP) by tedy mohl padnout kvůli `openssl`,
nikoliv kvůli `fusermount`. Navíc `nvp_fuse_helper` (binární, volaný `nvp_fuse.sh`) je gitignored
→ `nvp_emulator/` FUSE cesta nikdy nemůže fungovat z buildnutého ZIPu (chybí helper).

---

## 8. Lairy / nekonzistence / neotřelé otázky

1. **`update-binary` je stub (`exit 0`).** TWRP flash → `customize.sh` se nespustí → NVP+permisse
   se nenastaví. ✅ Instalovat jen přes Magisk app. (Nebo doplnit stock installer.)
2. **SELinux `permissive *` (post-fs-data.sh:56).** `magiskpolicy --live "permissive *"` dělá
   celý systém permissive, ne jen modul. Nahradit konkrétní pravidly pro `u:object_r:system_lib_file:s0`
   apod., nebo potvrdit jako záměrné.
3. **`nvp_emulator/` nikde nevolán (kromě gen_nvp_binary.sh).** Paralýza — lepší toolkit, ale neaktivní.
   Rozhodni: (a) zrušit `nvp_emulator/`, (b) přepojit boot, (c) sjedunit.
4. **`nvp_emulator/README.md` je zastaralý.** Říká "9 scriptů" (je jich **8** — table má 0–7) a
   "automatically installed when flashed" (**lže** — nikdo ho nevolá). Musí být regenerován.
5. **`module/bin/openssl` je 32-bit ARMhf glibc** — payload neobsahuje armhf libc → **openssl
   lze spustit jen s doplnitkem armhf stromu**. Ověřit na device před použitím.
6. **`bin/init_nvp` je shell script**, který sourcuje `/vendor/usr/data/icx_nvp.cfg`. Ten config
   **není v payloadu** → `init_nvp` selže (sh `. nonexistent` = exit 1), ale nikdo nevolá → ignorovat.
7. **`function.sh` není sourced** (verify `grep` prázdný) → mrtý kód. Odstranit nebo označit.
8. **ERRR workaround (service.sh:393-415).** Loop čeká na `persist.vendor.izmprop.initialized=true`.
   Pokud HAL nikdy nenastartuje (neSony HW), loop dojede do 15s a pokračuje. OK, ale
   `resetprop -p --delete` na `persist.vendor.audio.mixerthread.res` + `std` přepis může chovat
   podivně; ověřit v logcatu.
9. **`system_mode/`** (root projektu) = live EFS dump z device (gitignored). Obsahovat může
   `init.insmod.sh`, `filezip.sh`, `icx_syslog` atp. — použít jako referenci pro to, co vůbec
   na device existuje, ne jako build source.

---

## 9. Rychlý referenční index

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
| Sony proprietární HAL/lib | `module/system/` (gitignored, read-only snapshot) |
| **Hlavní audio HAL** (2,7 MB, effect pipeline) | `module/system/vendor/lib64/hw/audio.primary.icx1295.so` |
| **Shim/entrypoint HAL** (420 KB, DT_NEEDED→icx1295) | `module/system/vendor/lib64/hw/audio.primary.msm8996.so` |
| IZM/NVP property reader (FIX B1 zdroj) | `module/system/vendor/lib64/libizmproperties.so` |
| HIDL property service | `module/system/vendor/bin/hw/izm.android.properties@1.0-service` |
| IDD service | `module/system/vendor/bin/hw/vendor.semc.system.idd@1.0-service` |
| GNU binárky (fusermount/openssl/idds) | `module/system/bin/` |
| glibc loader chain | `module/system/lib/aarch64-linux-gnu/` |
| A2DP HAL | `module/system/vendor/lib64/hw/audio.a2dp.icx1295.so` |
| Efektní koeficienty | `module/system/vendor/etc/` (kompletní, viz §6.3) |
| Aktivní NVP generátor | `module/nvp_emulator/gen_nvp_binary.sh` |
| NEPoužité NVP toolkit | `module/nvp_emulator/{nvp_emulator,nvp_wrapper,nvp_daemon,setup_nvp_emulator,nvp_fuse,integrate_with_service,init_nvp}.sh` |
| Magisk env helpery | `module/function.sh` — **mrtý (není sourced)** |
| DT_NEEDED shim pattern | skill `add-dlopen-dependency-android-so` |
| ELF/glibc patch bez root | skill `android-elf-patching` |

---

## 10. Odhaleny vztah: DT_NEEDED shim = `add-dlopen-dependency-android-so`

`audio.primary.msm8996.so` je **živým příkladem** skillu `add-dlopen-dependency-android-so`:
`patchelf --add-needed "/vendor/lib/hw/audio.primary.icx1295.so"` přidal první `DT_NEEDED`
jako absolutní cestu (basename by `hw/` podadresář nemohl najít — viz pitfall #4 z skillu).
`readelf -d` potvrzuje `Shared library: [/vendor/lib/hw/audio.primary.icx1295.so]` jako první
NEEDED → linker ho řeší jako první (prepend), `dlopen`ne icx1295 před kódem shimu. To je
přesně pattern, který skill řeší (Android 8+/API 26+ akceptuje absolutní `DT_NEEDED`).
Strukturně OK (`readelf -d` clean); **runtime verdict jen z logcatu** (`dlopen|cannot|icx1295|audio.primary.*fail`).
