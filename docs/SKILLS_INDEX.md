# Walkman Port — Skills Index

**Účel:** jediný přehled, který **hermes skill** použít na který port problém —
nepotřebuješ hledat. Každý skill → co dělá → kde je → jak ho použít na TOMHLE projektu.

> Verze: 2025-08-14. Všechny skills níže jsou potvrzené jako `setup_needed: false` (ready).

---

## A. ELF / HAL patching  ← nejpoužívanější

| Co potřebuješ | Skill | Použití na projektu | Kde je |
|---|---|---|---|
| Přidat `DT_NEEDED` (absolutní cesta i do `hw/`) | `add-dlopen-dependency-android-so` | **`audio.primary.msm8996.so` má `DT_NEEDED: /vendor/lib/hw/audio.primary.icx1295.so` — přesně tento pattern!** Potřebuješ jen `patchelf --add-needed "/vendor/lib/hw/audio.primary.icx1295.so" audio.primary.msm8996.so`. Strukturní check `readelf -d` ≠ runtime — otestovat `linker <so>` + logcat. | `~/.hermes/skills/add-dlopen-dependency-android-so/SKILL.md` |
| Patch `.so` bez root (patchelf, integrity, arch check) | `android-elf-patching` | glibc↔Bionic `.so` chain (msm8996→icx1295), arch match (aarch64 vs armhf), termux write workaround (`$TMPDIR`). Obsahuje `references/patchelf-android.md` + `scripts/dlopen_inject_probe.py`. | `~/.hermes/skills/android-elf-patching/SKILL.md` |

**Pamatu:** `audio.primary.msm8996.so` = **shim** (420 KB), nikoli hlavní HAL.
Hlavní HAL = `audio.primary.icx1295.so` (2,7 MB, `vendor/lib64/hw/`). Vždycky verify oba:
`readelf -d .../msm8996.so | grep NEEDED` a `readelf -d .../icx1295.so | grep NEEDED`.

---

## B. Projekt lokální skills (v `.hermes/skills/` → `hermes skill plan`)

| Skill | Co dělá | Kdy použít |
|---|---|---|
| `walkman-port-playbook` | Master playbook: NVP node map (000–242), FIX B1, inline NVP init v service.sh/post-fs-data.sh, coef inventory, DT_NEEDED shim mechanism. | Kdykoli nevíš, jak NVP/HAL funguje. |
| `android-emulator-skill` | Termux Android tooling / ADB bridge. | ADB push/pull, `linker` probe, device logcat. |
| `shellcheck` (přes `shell`) | Lint `.sh` soubory. | `shellcheck module/*.sh module/nvp_emulator/*.sh` — CI kontroluje. |

---

## C. CI / linting  (`.github/workflows/ci.yml`)

| Co | Jak | Skill/komponent |
|---|---|---|
| Shell check | `shellcheck module/*.sh` | build-in (ci.yml) |
| C/C++ analyze | `clang --analyze src/effect.cpp` | build-in (ci.yml + `Application.mk`) |
| C++ tidy | `clang-tidy` | build-in (ci.yml) |
| `.sh` syntax | `bash -n` | `bash -n module/*.sh` (všechny OK) |

---

## D. Hermes agent itself  (NEUPDATOVAT — zamčeno 0.16.0)

| Co | Skill | Proč |
|---|---|---|
| `hermes update` BLOKUJEME | `hermes-agent` | 0.19.0 má `PROJECT_ROOT` NameError + `cryptography` má no manylinux wheel pro Bionic. Constraint v `~/.config/pip/pip.conf` → `hermes-agent==0.16.0`. **Nikdy neupgradovat.** |
| Konfigurace / skills | `hermes-agent` | `hermes config`, `hermes skills`, `hermes setup`. |
| Pip constraints | `devops` (`fix-cryptography-android-termux`) | `~/.config/pip/pip.conf` + `~/.hermes/pip-constraints.txt` blokuje C-extension wheels. |

---

## E. Rychlé rozhodování — "co použít, kdy"

- **Potřebuješ přidat `.so` jako závislost jinému `.so` v `hw/`?** → `add-dlopen-dependency-android-so`
  (to je přesně `msm8996.so → icx1295.so`).
- **Potřebuješ patchelf/glibc `.so` na Androidu bez root?** → `android-elf-patching`.
- **Potřebuješ pochopit NVP node/offset/FIX B1?** → `walkman-port-playbook` + `module/nvp_emulator/gen_nvp_binary.sh`.
- **Potřebuješ pochopit boot lifecycle?** → `docs/MODULE_ARCHITECTURE.md` §1.3–§4.
- **Potřebuješ pochopit, proč `openssl` padá?** → `docs/MODULE_ARCHITECTURE.md` §7 (`32-bit ARMhf glibc`, žádný loader v payloadu).
- **Potřebuješ pochopit, co je hlavní HAL?** → `docs/MODULE_ARCHITECTURE.md` §2.1 (`icx1295.so` = hlavní, `msm8996.so` = shim).

---

## F. Projektové soubory → skill mapa

| Projektový problém | Dotčený skill | Referenční soubory |
|---|---|---|
| `DT_NEEDED` shim msm8996→icx1295 | `add-dlopen-dependency-android-so` | `module/system/vendor/lib64/hw/audio.primary.msm8996.so`, `docs/§10` |
| glibc/Bionic ELF integrity | `android-elf-patching` | `module/system/bin/`, `module/system/lib/aarch64-linux-gnu/`, `recreate_symlinks.sh` |
| NVP emulator (dual impl) | `walkman-port-playbook` | `module/nvp_emulator/`, `module/service.sh:182-190,232-238,298`, `module/post-fs-data.sh:98-107` |
| Efekty nefungují | `walkman-port-playbook` + `android-elf-patching` | `docs/§6` (coefs všechny v `vendor/etc/`), `service.sh` resetprop |
| CI pipeline | `shellcheck` / clang | `.github/workflows/ci.yml`, `module/Application.mk` |

---

## G. Known issues (runtime, potvrzené na device)

| Problém | Kde | Status | Skill / akce |
|---|---|---|---|
| `icx_syslog` missing → silent cmd-not-found | `module/service.sh:421` | **FIXED** `8b68503` — if/else guard + warn log | — (sh guard) |
| `sepolicy.rule/.pfsd` neexistují → `sepolicy_sh` no-op | `module/post-fs-data.sh:76-86` | **FIXED** `8b68503` — `[ -f ]` guard, fall back na `permissive()` | — (sh guard) |
| 64-bit `icx1295.so` TEXTREL + BIND_NOW → Android 11 linker risk | `module/system/vendor/lib64/hw/` | **ACCEPTED** — source není, rebuild impossible; workaround `LD_LIBRARY_PATH=/vendor/lib` | `android-elf-patching`, `add-dlopen-dependency-android-so` |
| `effect.cpp` = HAL stub (žádný DSEE DSP) | `src/effect.cpp` (68 l.) | **OPEN** — exportuje `walkman_effect_interface`, ale `process()` return 0 (nepracuje). `icx1295.so` obsahuje kompletní `EffectExecuteDPFDSX/VPT/Vinyl` + `.rodata` 1,12 MB coefs | viz §H |
| armhf `openssl` broken (`ld-linux-armhf.so.3` missing v runtime) | `module/system/bin/openssl` | **DEAD** — nikdy volán module skripty | viz §6.3 |
| `load_sony_driver` volaný z `init.icx1295.rc` **i** `service.sh:391` | `system_mode/`, `module/service.sh` | **FIXED** `bf12236` — prop-gated (`getprop`) | — |
| 32-bit shim `msm8996.so` DT_NEEDED → 32-bit `icx1295.so` | `module/system/vendor/lib/hw/` | **OK** — `/vendor/lib/hw/...` potvrzeno `readelf -d` | — |
| 64-bit shim `msm8996.so` DT_NEEDED → 32-bit cesta ❌ | `module/system/vendor/lib64/hw/` | **FIXED** `2b50c48` — dříve `/vendor/lib/hw/...` (ELF class mismatch pro `linker64`), opraveno na `/vendor/lib64/hw/...` (`patchelf --replace-needed`) | verify: `readelf -d lib64/hw/audio.primary.msm8996.so \| grep NEEDED` |

---

## H. DSP / DSEE reverse-engineering status

`icx1295.so` (2,7 MB, `vendor/lib64/hw/`) **není jen dispatch** — obsahuje kompletní DSP. Potvrzeno:
- `nm -D` exportuje `T`: `CalcCoefficient`, `EffectExecuteDPFAttn`, `EffectExecuteDPFDSX`, `EffectExecuteDPFVPT`, `EffectExecuteF2I`, `EffectExecuteI2F`, `EffectExecuteVinyl` + `EffectFinalize/GetDelaySize/GetParam/GetVariable` varianty.
- `.rodata` = **1 122 360 B** (72 % blobu) — obsahuje **všechny DSP koeficienty** (ClearPhase lps, DSEE bin/dcfg, DSX, VPT, Vinyl).
- `DT_NEEDED` = `libasound.so` (ALSA) + HIDL stack → standardní Bionic chain, kompatibilní s `linker64`.

**2 cesty k funkčnímu portu:**
1. **Link-on-existing** — `src/effect.cpp` stub zavolá `icx1295.so` `EffectExecuteDPFDSX` (exported T) přes `dlopen`/`dlsym`. Rychlé, ale TEXTREL risk na Android 11.
2. **Recompile DSP** — ghidra/odpal `EffectExecuteDPX` + `.rodata` koeficienty → C++ do `src/effect.cpp`. Čistý, ale rozsáhlý (2,7 MB blob, ~1 MB `.rodata`).

Rozhodování je uživatelské (source code Sony není k dispozici).
