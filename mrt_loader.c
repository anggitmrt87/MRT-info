#include <dlfcn.h>
#include <unistd.h>
#include <android/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#define LOG_TAG "MRTLoader"

#ifndef LIB_PATH
#error "LIB_PATH must be defined"
#endif

static int file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0);
}

int main(int argc, char **argv) {
    if (!file_exists(LIB_PATH)) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "File not found: %s", LIB_PATH);
        return 1;
    }
    void *handle = dlopen(LIB_PATH, RTLD_NOW);
    if (!handle) {
        const char *err = dlerror();
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "dlopen failed: %s", err ? err : "unknown");
        return 1;
    }
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Loaded: %s", LIB_PATH);
    sleep(2);
    dlclose(handle);
    return 0;
}