#ifndef WALKMAN_AUDIO_EFFECT_H
#define WALKMAN_AUDIO_EFFECT_H

#include <stdint.h>
#include <sys/cdefs.h>
#include <stddef.h>

__BEGIN_DECLS

/* Walkman effect descriptor */
typedef struct {
    uint32_t type;
    uint32_t version;
    const char *name;
    const char *implementor;
} walkman_effect_descriptor_t;

/* Walkman effect interface */
typedef struct {
    int (*init)(void *context);
    int (*process)(void *context, void *in, void *out, size_t frames);
    int (*release)(void *context);
    int (*set_parameter)(void *context, int tag, void *value, size_t size);
    int (*get_parameter)(void *context, int tag, void *value, size_t *size);
} walkman_effect_interface_t;

/* Global descriptor */
extern const walkman_effect_descriptor_t walkman_effect_desc;

/* Global interface */
extern const walkman_effect_interface_t walkman_effect_interface;

__END_DECLS

#endif /* WALKMAN_AUDIO_EFFECT_H */
