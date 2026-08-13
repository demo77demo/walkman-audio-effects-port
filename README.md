# Walkman Audio Effects Port

Port Sony Walkman audio effects (DSEE, ClearAudio+, Clear Bass, S-Force 3D Surround, Hi-Res Audio)
pro OnePlus 3 (msm8996) / Android 11.

## Prehled

Tento projekt portuje audio efekty ze Sony Xperia zařízení do OnePluse 3. Cílová platforma je
Qualcomm Snapdragon 820 (msm8996) s Android 11. Projekt je strukturovan jako **Magisk modul**
s proprietárními knihovnami a HAL hooky.

## Obsah

### Zdrojová část (build)
- `src/` -- zdrojové kódy pro audio efekty (C/C++)
- `include/` -- HAL headery (`effect.h`)
- `Android.mk` -- AOSP / NDK `ndk-build` konfigurace (lokace: repo root)
- `module/Application.mk` -- NDK `APP_*` build config (ABI 64/32, API 29, c++17)
- `LICENSE` -- Apache 2.0

### Magisk modul (`module/`)
- `module/module.prop` -- metadata modulu (NE root `module.prop`)
- `module/customize.sh` -- setup během instalace (NVP data, set_perm)
- `module/service.sh` -- runtime daemon + HAL hook
- `module/post-fs-data.sh` -- symlinky před startem systému
- `module/recreate_symlinks.sh` -- obnova `/dev/icx_nvp/` symlinků
- `module/function.sh` -- helper funkce (mount mirror, cache, remount)
- `module/system.prop` -- systémové property
- `module/package.txt` -- seznam balíčků ke kontrole
- `module/META-INF/com/google/android/` -- flashable ZIP (update-binary, updater-script)
- `module/nvp_emulator/` -- userspace emulace ICX1295 NVP (čtíst, nepsát rootem)
- `module/system/` -- proprietární Sony .so bloby (gitignored — device dump)

### Zařízení / dump (NEcommit)
- `system/` -- moje .bak upravy (gitignored, device-side)
- `system_mode/` -- dump EFS: baterie/imei/cirrus (gitignored, device dump)
- `icx1295` -- symlink → gir clone ROM (root-owned, lokálně nefunkční)

## Podporování efekty

| Efekt | Popis | Status |
|-------|-------|--------|
| DSEE | Digital Sound Enhancement Engine | V plnění |
| ClearAudio+ | Komprese optimalizace | V plnění |
| Clear Bass | Nízké kmitočty | V plnění |
| S-Force 3D | Prostorový zvuk | Plánováno |
| Hi-Res | 24-bit/96kHz podpora | Plánováno |

## Instalace

1. Ujisti se, že máš root a Magisk
2. Flashni `walkman-audio-effects-port.zip` přes Magisk App
3. Reboot (pouze pokud je to tvé zařízení)
4. Ověř v logcat: `logcat -s WalkmanAudio`

## Vývoj

Strom:
```
.
├── Android.mk          # ndk-build z rootu (LOCAL_SRC_FILES = src/effect.cpp)
├── Application.mk      # (lokalní alias) nebo: ndk-build -C module/
├── README.md
├── LICENSE
├── AGENTS.md           # konvence / pravidla tohoto agenta
├── .gitignore
├── include/
│   └── effect.h
└── src/
    └── effect.cpp

module/                 # Magisk modul (flashovatelný .zip)
├── module.prop
├── customize.sh        # NVP gen + set_perm
├── service.sh          # runtime
├── post-fs-data.sh
├── recreate_symlinks.sh
├── function.sh
├── system.prop
├── package.txt
├── META-INF/
│   └── com/google/android/{update-binary,updater-script}
├── nvp_emulator/       # icx1295 NVP userspace emulace
└── system/             # proprietární .so (device -> gitignored)
```

Build pro AOSP:
```
mmm hardware/oneplus/walkman-audio-effects-port/
```

Pro standalone NDK build (v rootu; `Android.mk` ukazuje na `src/effect.cpp` + `include/`):
```
ndk-build -j$(nproc)
```
> `module/Application.mk` není pro root build použity — slouží kompilacivnímu kontextu modulu. Chceš-li ho použít, přesuň ho do repo rootu nebo spusť `ndk-build` z `module/` a přesuň `Android.mk` tam, kde `Application.mk` je.

## Testování

Po instalaci ověř funkčnost pomocí:
- `dumpsys media.audio_flinger` -- kontrola registrovaných efektů
- `logcat -s WalkmanAudio:V *:S` -- diagnostické logy

Runtime verifikace je povinná -- strukturní kontrola (readelf/objdump)
nenahrazuje skutečný test na zařízení s logcatem.

## Upozornění

- Tento modul upravuje systémové audio HAL komponenty
- Vždy zálohuj stock ROM před instalací
- Neinstaluj na produkční zařízení bez testování
- `module/nvp_emulator/` a `module/system/` jsou device-dumpy (root-owned) -- upravuj pouze na zařízení s příslušnými právy

## Licence

Apache 2.0 -- viz `LICENSE`
