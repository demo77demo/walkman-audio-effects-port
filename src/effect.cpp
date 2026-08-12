/*
 * Walkman Audio Effects Port
 *
 * Port Sony Walkman audio effects (DSEE, ClearAudio+, Clear Bass)
 * pro OnePlus 3 (msm8996) / Android 11.
 *
 * Licensed under the Apache License, Version 2.0
 */

#include <log/log.h>
#include <cstring>
#include <cerrno>
#include <cstdlib>

#include "effect.h"

#define WALKMAN_LOG_TAG "WalkmanAudio"

const walkman_effect_descriptor_t walkman_effect_desc = {
    .type = 0x00010000,  /* DSEE effect type */
    .version = 0x00010001,
    .name = "Walkman DSEE",
    .implementor = "demo77demo",
};

static int effect_init(void *context) {
    ALOGI("%s: initializing Walkman DSSE effect", WALKMAN_LOG_TAG);
    return 0;
}

static int effect_process(void *context, void *in, void *out, size_t frames) {
    if (!in || !out || frames == 0) {
        ALOGE("%s: invalid parameters (in=%p, out=%p, frames=%zu)",
              WALKMAN_LOG_TAG, in, out, frames);
        return -EINVAL;
    }
    ALOGV("%s: processing %zu frames", WALKMAN_LOG_TAG, frames);
    return 0;
}

static int effect_release(void *context) {
    ALOGI("%s: releasing Walkman DSSE effect", WALKMAN_LOG_TAG);
    return 0;
}

static int effect_set_parameter(void *context, int tag, void *value, size_t size) {
    if (!value || size == 0) {
        return -EINVAL;
    }
    ALOGV("%s: set parameter tag=0x%x size=%zu", WALKMAN_LOG_TAG, tag, size);
    return 0;
}

static int effect_get_parameter(void *context, int tag, void *value, size_t *size) {
    if (!value || !size) {
        return -EINVAL;
    }
    ALOGV("%s: get parameter tag=0x%x", WALKMAN_LOG_TAG, tag);
    return 0;
}

const walkman_effect_interface_t walkman_effect_interface = {
    .init = effect_init,
    .process = effect_process,
    .release = effect_release,
    .set_parameter = effect_set_parameter,
    .get_parameter = effect_get_parameter,
};
