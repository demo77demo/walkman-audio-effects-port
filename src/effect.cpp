/*
 * Walkman Audio Effects Port
 *
 * Port Sony Walkman DSP effects (DSEE HX, DSEE Ultimate, VPT, Vinyl)
 * pro OnePlus 3 (msm8996) / Android 11.
 *
 * Architecture: dlopen bridge to audio.primary.icx1295.so
 *   effect.cpp (libwalkmanaudioeffect) --dlopen/dlsym--> EffectExecuteDPFDSX()
 *
 * icx1295.so exports (verified via `nm -D`):
 *   EffectExecuteDPFDSX  — DSEE HX/DSF processing
 *   EffectExecuteDPFVPT   — 360 Reality Audio / VPT
 *   EffectExecuteVinyl     — Vinyl Processor
 *   EffectExecuteF2I/I2F   — float<->int conversion helpers
 *   DPFvpt_er_init         — DSP engine init
 *   EffectFinalizeDPF*     — cleanup / finalize
 *   EffectGetParamDPF*     — get/set DSP parameters
 *   EffectGetDelaySizeDPF* — buffer delay size query
 *
 * Signature (verified AArch64 disassembly @0x11890c):
 *   int EffectExecuteDPFDSX(void *config_table, void *runtime_state);
 *   - x0, x1 only — both null-checked, dereferenced
 *   - x2-x7 unused as inputs (scratch locals)
 *
 * Licensed under the Apache License, Version 2.0
 */
#include <log/log.h>
#include <dlfcn.h>
#include <cstring>
#include <cerrno>
#include <cstdlib>

#include "effect.h"

#define WALKMAN_LOG_TAG "WalkmanAudio"
#define ICX1295_SO_PATH "/vendor/lib64/hw/audio.primary.icx1295.so"

/* Function types — based on AArch64 disassembly (2 pointer params, int ret) */
typedef int (*effect_execute_fn)(void *config, void *runtime);
typedef int (*effect_init_fn)(void *config, void *runtime);
typedef int (*effect_finalize_fn)(void *config, void *runtime);

/* Runtime state for the dlopen bridge */
struct walkman_effect_state {
    void            *so_handle;
    effect_init_fn   dpf_init;
    effect_execute_fn dpf_dsx;
    effect_execute_fn dpf_vpt;
    effect_execute_fn vinyl;
    effect_finalize_fn dpf_finalize;
    void            *icx_config;   /* populated by dpf_init */
    void            *icx_runtime;  /* populated by dpf_init */
};

const walkman_effect_descriptor_t walkman_effect_desc = {
    .type = 0x00010000,   /* DSEE effect type */
    .version = 0x00010002,
    .name = "Walkman DSEE",
    .implementor = "demo77demo",
};

/*
 * Try RTLD_DEFAULT first (icx1295.so may already be loaded by audio HAL
 * via the DT_NEEDED shim). Fall back to explicit dlopen for standalone use.
 */
static int bridge_resolve(struct walkman_effect_state *st) {
    if (st->dpf_dsx) return 0;  /* already resolved */

    /* Attempt 1: symbol already in process (shim already loaded icx1295) */
    st->dpf_dsx  = (effect_execute_fn)dlsym(RTLD_DEFAULT, "EffectExecuteDPFDSX");
    st->dpf_vpt  = (effect_execute_fn)dlsym(RTLD_DEFAULT, "EffectExecuteDPFVPT");
    st->vinyl    = (effect_execute_fn)dlsym(RTLD_DEFAULT, "EffectExecuteVinyl");
    st->dpf_init = (effect_init_fn)dlsym(RTLD_DEFAULT, "DPFVpt_er_init");
    st->dpf_finalize = (effect_finalize_fn)dlsym(RTLD_DEFAULT, "EffectFinalizeDPFDSX");

    if (st->dpf_dsx) {
        ALOGI("%s: icx1295 symbols resolved via RTLD_DEFAULT", WALKMAN_LOG_TAG);
        return 0;
    }

    /* Attempt 2: explicit dlopen */
    st->so_handle = dlopen(ICX1295_SO_PATH, RTLD_NOW | RTLD_LOCAL);
    if (!st->so_handle) {
        ALOGE("%s: dlopen(%s) failed: %s", WALKMAN_LOG_TAG,
              ICX1295_SO_PATH, dlerror());
        return -ENODEV;
    }
    st->dpf_dsx  = (effect_execute_fn)dlsym(st->so_handle, "EffectExecuteDPFDSX");
    st->dpf_vpt  = (effect_execute_fn)dlsym(st->so_handle, "EffectExecuteDPFVPT");
    st->vinyl    = (effect_execute_fn)dlsym(st->so_handle, "EffectExecuteVinyl");
    st->dpf_init = (effect_init_fn)dlsym(st->so_handle, "DPFVpt_er_init");
    st->dpf_finalize = (effect_finalize_fn)dlsym(st->so_handle, "EffectFinalizeDPFDSX");

    if (!st->dpf_dsx) {
        ALOGE("%s: dlsym EffectExecuteDPFDSX failed: %s", WALKMAN_LOG_TAG, dlerror());
        dlclose(st->so_handle);
        st->so_handle = nullptr;
        return -ENODEV;
    }
    ALOGI("%s: icx1295 symbols resolved via dlopen(%s)", WALKMAN_LOG_TAG, ICX1295_SO_PATH);
    return 0;
}

static int effect_init(void *context) {
    if (!context) {
        ALOGE("%s: init called with null context", WALKMAN_LOG_TAG);
        return -EINVAL;
    }
    struct walkman_effect_state *st = (struct walkman_effect_state *)context;
    memset(st, 0, sizeof(*st));

    int ret = bridge_resolve(st);
    if (ret) {
        ALOGW("%s: icx1295 not available — stub mode (DSEE will passthrough)",
              WALKMAN_LOG_TAG);
        return ret;  /* not fatal — framework falls back to passthrough */
    }

    /*
     * TODO(device-test): DPFvpt_er_init signature unknown (RE needed).
     * Disassembly of DPFvpt_er_init @0x133238 shows 2-3 pointer params.
     * On device: call with icx1295 HAL-provided config to populate
     * icx_config + icx_runtime, then verify process() works with logcat.
     */
    ALOGI("%s: Walkman DSEE effect initialized (DSX=%p, VPT=%p, Vinyl=%p)",
          WALKMAN_LOG_TAG, st->dpf_dsx, st->dpf_vpt, st->vinyl);
    return 0;
}

static int effect_process(void *context, void *in, void *out, size_t frames) {
    if (!context || !in || !out || frames == 0) {
        return -EINVAL;
    }
    struct walkman_effect_state *st = (struct walkman_effect_state *)context;

    if (!st->dpf_dsx || !st->icx_runtime) {
        /* icx1295 not loaded / runtime not initialized — passthrough */
        ALOGV_ONCE("%s: process() passthrough (no DSP state)", WALKMAN_LOG_TAG);
        return 0;
    }

    /*
     * TODO(device-test): Map in/out audio buffers into icx_runtime struct.
     * The HAL provides audio PCM in the runtime context struct fields
     * (layout unknown — needs memory inspection via logcat + objdump).
     *
     * Expected flow:
     *   1. Copy `in` (frames * channels * sizeof(sample)) into icx_runtime input field
     *   2. Call: st->dpf_dsx(st->icx_config, st->icx_runtime)
     *   3. Copy icx_runtime output field into `out`
     *
     * Verify with: logcat | grep WalkmanAudio
     */
    ALOGV("%s: process(%zu frames) — DSX bridge ready, buffer mapping TODO",
          WALKMAN_LOG_TAG, frames);
    return 0;
}

static int effect_release(void *context) {
    if (!context) return -EINVAL;
    struct walkman_effect_state *st = (struct walkman_effect_state *)context;

    if (st->dpf_finalize && st->icx_runtime) {
        st->dpf_finalize(st->icx_config, st->icx_runtime);
    }
    if (st->so_handle) {
        dlclose(st->so_handle);
        st->so_handle = nullptr;
    }
    ALOGI("%s: Walkman DSEE effect released", WALKMAN_LOG_TAG);
    return 0;
}

static int effect_set_parameter(void *context, int tag, void *value, size_t size) {
    if (!value || size == 0) return -EINVAL;
    struct walkman_effect_state *st = (struct walkman_effect_state *)context;

    /*
     * TODO(device-test): Map tag to icx1295 EffectGetVariable/SetVariable.
     * Tags from Android audio effect framework (e.g. EFFECT_PARAM_*).
     * On device: test with logcat to trace param flow.
     */
    ALOGV("%s: set_parameter tag=0x%x size=%zu", WALKMAN_LOG_TAG, tag, size);
    return 0;
}

static int effect_get_parameter(void *context, int tag, void *value, size_t *size) {
    if (!value || !size) return -EINVAL;
    struct walkman_effect_state *st = (struct walkman_effect_state *)context;

    ALOGV("%s: get_parameter tag=0x%x", WALKMAN_LOG_TAG, tag);
    return 0;
}

const walkman_effect_interface_t walkman_effect_interface = {
    .init = effect_init,
    .process = effect_process,
    .release = effect_release,
    .set_parameter = effect_set_parameter,
    .get_parameter = effect_get_parameter,
};
