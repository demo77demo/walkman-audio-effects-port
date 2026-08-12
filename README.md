# Walkman Audio Effects Port

Port Sony Walkman audio effects (DSEE, ClearAudio+, Clear Bass, S-Force 3D Surround, Hi-Res Audio)
pro OnePlus 3 (msm8996) / Android 11.

## Prehled

Tento projekt portuje audio efekty z Sony Xperia zarizeni do OnePluse 3. Cilova platforma je
Qualcomm Snapdragon 820 (msm8996) s Android 11. Projekt je strukturovan jako Magisk module
s proprietarnimi knihovnami a HAL hooky.

## Obsah

- `src/` -- zdrojove kody pro audio efekty (C/C++)
- `include/` -- hal header soubory
- `Android.mk` -- AOSP/Magisk build konfigurace
- `module.prop` -- Magisk modul metadata
- `vendor/` -- proprietarni knihovny a konfigurace

## Podporovane efekty

| Efekt | Popis | Status |
|-------|-------|--------|
| DSEE | Digital Sound Enhancement Engine | V plneni |
| ClearAudio+ | Kompresni optimalizace | V plneni |
| Clear Bass | Nizke kmitočty | V plneni |
| S-Force 3D | Prostorove zvuky | Planovano |
| Hi-Res | 24-bit/96kHz podpora | Planovano |

## Instalace

1. Ujistete se, ze mate root a Magisk
2. Nahrani `walkman-audio-effects-port.zip` pres Magisk App
3. Reboot (pouze pokud je to vase zarizeni)
4. Ověřte v logcat: `logcat -s WalkmanAudio`

## Vyvoj

```
.
├── Android.mk
├── README.md
├── LICENSE
├── module.prop
├── include/
│   └── effect.h
└── src/
    └── effect.cpp
```

Build pro AOSP:
```
mmm hardware/oneplus/walkman-audio-effects-port/
```

Pro standalone NDK build:
```
ndk-build -j$(nproc)
```

## Testovani

Po instalaci overte funkcnost pomoci:
- `dumpsys media.audio_flinger` -- kontrola registrovanych efektů
- `logcat -s WalkmanAudio:V *:S` -- diagnostické logy

Runtime verifikace je povinná -- strukturní kontrola (readelf/objdump) nenahrazuje
skutečný device test s logcatem.

## Upozorneni

- Tento modul upravuje systémové audio HAL komponenty
- Vždy zálohujte stock ROM před instalací
- Neinstalujte na produkční zařízení bez testování

## Licence

Apache 2.0 -- viz `LICENSE`
