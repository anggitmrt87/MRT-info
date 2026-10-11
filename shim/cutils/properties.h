#ifndef CUTILS_PROPERTIES_SHIM_H
#define CUTILS_PROPERTIES_SHIM_H

/*
 * Shim for <cutils/properties.h> so we can build AOSP-style
 * sources with the standalone Android NDK.
 */

#include <string.h>
#include <sys/system_properties.h>

#ifndef PROP_VALUE_MAX
#define PROP_VALUE_MAX 92
#endif
#ifndef PROP_NAME_MAX
#define PROP_NAME_MAX 32
#endif

#ifdef __cplusplus
extern "C" {
#endif

static inline int property_get(const char *key, char *value, const char *def) {
    int len = __system_property_get(key, value);
    if (len <= 0) {
        if (def) {
            strncpy(value, def, PROP_VALUE_MAX - 1);
            value[PROP_VALUE_MAX - 1] = '\0';
            len = (int)strlen(value);
        } else {
            value[0] = '\0';
        }
    }
    return len;
}

static inline int property_set(const char *key, const char *value) {
    return __system_property_set(key, value);
}

#ifdef __cplusplus
}
#endif
#endif /* CUTILS_PROPERTIES_SHIM_H */
