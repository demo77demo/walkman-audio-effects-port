# Walkman Port — Skills Quick Reference

Jednoduchý grep-friendly souhrn všech skills / workflows použitelných na tomhle projektu.
Každá položka = `skill_view <name>` (lokálně instalované) nebo `hermes skills install <name>`
(pro catalogové). Kategorie dle použití.

---

## A. ELF / HAL patching (nejpouživanější)

| Skill | Příkaz | Co dělá | Kdy použít |
|---|---|---|---|
| `add-dlopen-dependency-android-so` | `skill_view add-dlopen-dependency-android-so` | DT_NEEDED shim na `audio.primary.msm8996.so` -> `icx1295.so` absolutní cestou | Rebuild shimu; fix 64-bit path mismatch |
| `android-elf-patching` | `skill_view android-elf-patching` | patchelf integrity, TEXTREL warning, 32/64-bit consistency | Verze pred deploy; `--replace-needed` pro broken DT_NEEDED |

```bash
# verify shim chain
readelf -d module/system/vendor/lib{64}/hw/audio.primary.msm8996.so | grep NEEDED
md5sum system/vendor/lib64/hw/audio.primary.msm8996.so module/system/vendor/lib64/hw/audio.primary.msm8996.so
```

## B. Android analysis

| Skill | Příkaz | Co dělá |
|---|---|---|
| `analyzing-android-malware-with-apktool` | `skill_view analyzing-android-malware-with-apktool` | APK dekompilace (SoundEffectApp, IzmAudioManager) |
| `reverse-engineering-android-malware-with-jadx` | `skill_view reverse-engineering-android-malware-with-jadx` | DEX decompilace na source |
| `mobile-code-review-pro` | `skill_view mobile-code-review-pro` | Code review iOS/Android |

## C. Code quality / development

| Skill | Příkaz | Co dělá |
|---|---|---|
| `cpp-pro` | `skill_view cpp-pro` | Modern C++ pro `src/` (effect.cpp, nvp_validator) |
| `tdd` | `skill_view tdd` | RED-GREEN-REFACTOR na tests/test_nvp_validator |
| `code-review` | `skill_view code-review` | PR review pred commitem |

## D. Hermes / tooling

| Skill | Příkaz | Co dělá |
|---|---|---|
| `hermes-agent` | `skill_view hermes-agent` | Hermes konfig, CLI, modely, providers |
| `android-testing` | `skill_view android-testing` | Unit/integration test strategie |

## E. Project-local skills

Full index: `docs/SKILLS_INDEX.md`. Key skills:
- `add-dlopen-dependency-android-so` — DT_NEEDED shim pattern
- `android-elf-patching` — patclelf `--replace-needed`, TEXTREL, arch consistency

## Quick workflow

```bash
# 1. Edit v system/ (workdir) — NIKDY v module/system/
# 2. patchelf --replace-needed OLD NEW system/vendor/lib64/hw/audio.primary.msm8996.so
# 3. md5sum system/...so module/...so  # must match (4804a2b2)
# 4. git add docs/ && git commit -m "..." && git push && gh pr create
```

## Directory conventions (ze .gitignore)

| Dir | Role | Git tracked? |
|---|---|---|
| `system/` | WORK — .bak, debug logy, patched kopie | NO (gitignored) |
| `module/` | FINAL — source skripty + META-INF | YES (scripts only) |
| `module/system/` | flash-time payload (Sony blobs) | NO (gitignored) |
| `system_mode/` | LIVE device snapshot (read-only) | NO (gitignored) |
| `icx1295/` | symlink na Gir ROM | NO (gitignored) |
| `src/` | NDK source (C++) | YES |
| `tests/` | test source | YES |
| `docs/` | dokumentace | YES |
| `build/` | build artifacts | NO |
