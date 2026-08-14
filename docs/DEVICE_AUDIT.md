# DEVICE_AUDIT — Walkman Audio Effects Port na OnePlus 3 (msm8996 / Android 11)

Verze: 2026-08-14. Fakticky ověřeno `readelf`, `file`, `grep -rn`, `git ls-files`,
`git rm --dry-run`. **Nic není odhadnuté** — pokud není uvedeno `verified`, hledej v tabulce níže.

## 1. Tři vrstvy projektu (klíčové rozlišení)

| vrstva | co | kde | git? | writable? |
|---|---|---|---|---|
| **source (Magisk)** | co se flashuje jako module | `module/` (kromě `module/system/`) | ano | ano (u0_a331) |
| **flash-time payload** | binární artefakty zkopírované do systému | `module/system/` | **NE** (.gitignore: `bin/`, `*.so`, `*.bin`) | ano, ale root-owned (NEmazat bez su — zakázáno) |
| **device pevno (snapshot)** | snapshot fyzického /vendor+/lib+efs | `system_mode/` | **NE** (.gitignore:85 `system_mode/`) | ne — read-only referenční |

`**module/system/**` je **gitignored** — nikdo ji nepouští jako source. Je to
flash-time image. Per AGENTS.md: **nikdy neměnit jako source**.

`/tmp` neexistuje (Bionic readonly fs) → všechny diff/verify příkazy používají absolutní RP.

## 2. Tabulka binárek (faktická)

Ověřeno `file` + `readelf -d` (pro INTERP/NEEDED):

| soubor | arch | linker/INTERP | volá ho module/*.sh? | stav |
|---|---|---|---|---|
| `openssl` | ARM 32-bit, glibc 2.25-era | `/lib/ld-linux-armhf.so.3` | **NE** (grep empty) | 💀 mrtý v Magisk; armhf runtime chybí v module |
| `ld-2.25.so` | aarch64, glibc 2.25 | aarch64 ld | `recreate_symlinks.sh:7` (`fusermount`) | živý (pro fusermount) |
| `fusermount` | aarch64, glibc | `ld-linux-aarch64.so.1` | **NE** | 💀 FUSE větev mrtvá |
| `idds` | aarch64, **Bionic** (Android 28) | `/system/bin/linker64` | init rc | ✅ živý (semc.system.idd service) |
| `tinycap`, `tinyplay` | aarch64, Bionic | `/system/bin/linker64` | **NE** (stock) | 📦 stock nástroje |
| `start_initialize`, `start_diag`, `tool_*` | shell | sh | **NE** | 💀 mrtý v module kontextu |
| `logcopy.sh`, `optcopy.sh`, `precopy.sh` | shell | sh | **NE** | 💀 mrtý v module kontextu |

Poznámka k openssl: jeho `NEEDED` obsahuje `ld-linux-armhf.so.3` + 11 armhf glibc
libs (`libc.so.6`, `libssl.so`, `libcrypto.so`, `libglibc_bridge.so`, `libcxxrt.so.1`,
`libdl.so.2`, `librt.so.1`, `libpthread.so.0`, `libc++.so.1`, `libm.so.6`, `libgcc_s.so.1`).
Všechny jsou dostupné **jen** v `system_mode/lib/` (device pevno), **nikoliv** v
`module/system/lib/aarch64-linux-gnu/` (to je aarch64 sadu pro `fusermount`).

## 3. Tracked mrtý kód (kandidáti na `git rm`, **revertovatelné**)

Všechny `u0_a331`-owned a tracked. `bash -n` prošly všechny.

| soubor | proč mrtý |
|---|---|
| `module/function.sh` | `grep -rn "source.*function.sh"` prázdný — **nikdy** sourced |
| `module/nvp_emulator/init_nvp.sh` | nikdo nevolá (customize.sh má `set_perm`, ne volání) |
| `module/nvp_emulator/nvp_fuse.sh` | nikdo nevolá |
| `module/nvp_emulator/nvp_emulator.sh` | nikdo nevolá |
| `module/nvp_emulator/nvp_daemon.sh` | nikdo nevolá |
| `module/nvp_emulator/nvp_wrapper.sh` | nikdo nevolá |
| `module/nvp_emulator/setup_nvp_emulator.sh` | nikdo nevolá |
| `module/nvp_emulator/integrate_with_service.sh` | nikdo nevolá |
| `module/nvp_emulator/nvp_fuse_helper` | untracked (gitignored?), nikdo nevolá, FUSE dead |

**NEmazat** (živý): `gen_nvp_binary.sh` (customize.sh:18 + service.sh:237 fallback).

## 4. Tracked živý kód (call map)

```
customize.sh:8-10     set_perm gen_nvp_binary.sh, init_nvp.sh, nvp_fuse.sh, ...
customize.sh:18       sh gen_nvp_binary.sh $MODPATH/nvp_emulator/nvp_data  (INSTALL-TIME)
customize.sh:21-23    NODE0/22/138 = od -A n -t x1 read  (generuje .bin)
post-fs-data.sh:127   resetprop vendor.load_nvp_driver.init 1
service.sh:224        NVP_MODULE="$MODDIR/system/vendor/lib/modules/icx_nvp_emmc.ko"
service.sh:228        [ -e /dev/icx_nvp/000 ] && NVP_LOADED=1
service.sh:232-233    NVP_EMU_DIR / NVP_DATA_DIR
service.sh:237-238    FALLBACK: sh gen_nvp_binary.sh $NVP_DATA_DIR  (boot)
service.sh:301,324    nvpnode service loop
service.sh:308,324,331-333   *nvpflag / *nvpnode / *nvpinfo / *nvpstr / *nvp dispatch
service.sh:385-387   init.insmod.sh /vendor/etc/early.init.cfg ; /vendor/etc/icx_early.init.cfg ; load_sony_driver
```

## 5. Init rc duplicita (DOUBLE START)

`system_mode/system/vendor/etc/init/hw/init.icx1295.rc` (device pevno):
```
on early-init
    start early_init_sh
    start load_sony_driver
on init
    export CORE_REGISTER_FILE /vendor/etc/core_register
    export COMPONENT_REGISTER_FILE /vendor/etc/component_register
    export CONTENTPIPE_REGISTER_FILE /vendor/etc/contentpipe_register
```
vs `module/service.sh:385-386`:
```
init.insmod.sh /vendor/etc/early.init.cfg sys.all.early_init.ready
load_sony_driver sys.all.early_init.ready
```
→ `load_sony_driver` už běží jako init.rc service (`start load_sony_driver` na early-init);
`service.sh:386` volá ho **znovu** jako příkaz → riziko double-init a chyb z PATH.
`early.init.cfg` vs `early_init_sh` → také dualní mechanismus. **Nevymazávat** —
požadovat od uživatele, zda má service.sh:385-386 ruční volání odstranit.

## 6. OpenSSL arch-mismatch bug (ověřeno)

```
openssl DT_NEEDED (všechno armhf glibc):
  NEEDED ld-linux-armhf.so.3
  NEEDED libc.so.6
  NEEDED libssl.so
  NEEDED libcrypto.so
  ... (celkem 12 včetně ld-linux-armhf.so.3 jako NEEDED)
```
- Loader `/lib/ld-linux-armhf.so.3` (ARM 32-bit) **není v Magisk module** —
  `module/system/lib/` obsahuje jen `aarch64-linux-gnu/` sadu (pro fusermount).
- Armhf runtime celé sady je v `system_mode/lib/` (pevno), proto `openssl` funguje jen
  tehdy, když `system_mode/lib` mountuje jako `/lib/` — což není záručně v Magisk module.
- `recreate_symlinks.sh` línkuje **pouze aarch64** (8 záznamů všechny na
  `aarch64-linux-gnu/`). **Nikdy** neukazuje `ld-linux-armhf.so.3`→`/lib/ld-linux-armhf.so.3`.
- Důsledek: v Magisk runtime `openssl` selže s `no such file or directory` (interpreter
  missing), **ne** s chybou linku.
- `ld-2.25.so` v `module/system/bin/` je aarch64 → slouží `fusermount`, **ne** openssl.

## 7. Akční body (vyžadovaly uživatelský YES — destruktivní)

- [ ] `git rm` 8 tracked mrtých skriptů (section 3) — **vyžadovalo YES** (destructive, revertovatelné gitem)
- [ ] openssl: smazat (`module/system/bin/openssl` je gitignored+root-owned, ne volá se) nebo
      doplnit armhf glibc runtime do `module/system/lib/` a fix `recreate_symlinks.sh`
- [ ] `service.sh:385-386`: zrušit duplikátní `load_sony_driver`/`init.insmod.sh` volání (double-init)
- [ ] `customize.sh:9-10`: odkázat `set_perm` na smazané `init_nvp.sh`/`nvp_fuse.sh`

## 8. Potvrzené (verified)

```
readelf -d openssl  → 12 NEEDED (všechno armhf glibc)
file ld-2.25.so      → aarch64 (pro fusermount)
grep -rn openssl module/*.sh → empty
grep -rn "source.*function.sh" module → empty
git ls-files nvp_emulator/  → gen_nvp_binary.sh (alive) + 7 mrtých
file idds             → aarch64 Bionic (linker64) = živý (idd service)
check-ignore system_mode → .gitignore:85 (gitignored = pevno snapshot)
```
