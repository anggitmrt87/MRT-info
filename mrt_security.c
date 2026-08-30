/*
 * mrt_security.c
 * Security checker – menggunakan SHA256 internal.
 * EXPECTED_HASH akan dioverride dari Makefile dengan -D.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/system_properties.h>
#include <android/log.h>
#include <signal.h>
#include <ctype.h>
#include <errno.h>
#include <time.h>
#include "sha256.h"

#define LOG_TAG "MRT_Security"
#define CONFIG_FILE "/system/bin/mrt_loader"
#define SECURITY_PKG "com.chime.updatechecker"
#define SECURITY_ACTIVITY ".SecActivity"

#ifndef EXPECTED_HASH
#define EXPECTED_HASH ""
#endif

#define FAILURE_COUNT_FILE "/data/local/tmp/persist.mrt.failure_count"
#define MAX_FAILURES 3

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

static char* read_property(const char* key) {
    char value[PROP_VALUE_MAX];
    int len = __system_property_get(key, value);
    if (len > 0) {
        return strdup(value);
    }
    return NULL;
}

static char* read_file_content(const char* path) {
    FILE* f = fopen(path, "r");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = malloc(size + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t n = fread(buf, 1, size, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

static int write_file_content(const char* path, const char* content) {
    FILE* f = fopen(path, "w");
    if (!f) return -1;
    int r = fprintf(f, "%s", content);
    fclose(f);
    return (r >= 0) ? 0 : -1;
}

static char* resolve_file_path(const char* path) {
    struct stat st;
    if (lstat(path, &st) == 0) {
        if (S_ISREG(st.st_mode)) {
            return strdup(path);
        } else if (S_ISLNK(st.st_mode)) {
            char target[PATH_MAX];
            ssize_t len = readlink(path, target, sizeof(target)-1);
            if (len > 0) {
                target[len] = '\0';
                if (target[0] == '/') {
                    if (access(target, F_OK) == 0) return strdup(target);
                } else {
                    char dir[PATH_MAX];
                    strncpy(dir, path, sizeof(dir)-1);
                    dir[sizeof(dir)-1] = '\0';
                    char* last = strrchr(dir, '/');
                    if (last) {
                        *last = '\0';
                        char abs_path[PATH_MAX];
                        snprintf(abs_path, sizeof(abs_path), "%s/%s", dir, target);
                        if (access(abs_path, F_OK) == 0) return strdup(abs_path);
                    }
                }
            }
        }
    }
    return NULL;
}

static int is_package_installed(const char* pkg) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "/system/bin/pm list packages | grep -q '^package:%s$'", pkg);
    int ret = system(cmd);
    return (ret == 0);
}

static void launch_security_activity() {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
             "/system/bin/am start -W -n %s/%s --ez FROM_INIT true --ez FORCED true 2>&1",
             SECURITY_PKG, SECURITY_ACTIVITY);
    FILE* fp = popen(cmd, "r");
    if (fp) {
        char line[256];
        while (fgets(line, sizeof(line), fp)) {
            LOGI("%s", line);
        }
        pclose(fp);
    } else {
        LOGE("Failed to launch activity");
    }
}

static void force_shutdown() {
    LOGI("Triggering shutdown...");
    sleep(13);
    system("/system/bin/setprop sys.powerctl shutdown 2>/dev/null");
    exit(0);
}

static int read_failure_count() {
    char* content = read_file_content(FAILURE_COUNT_FILE);
    if (!content) return 0;
    int val = 0;
    for (char* p = content; *p; p++) {
        if (!isdigit(*p)) {
            free(content);
            return 0;
        }
    }
    val = atoi(content);
    free(content);
    return val;
}

static void write_failure_count(int count) {
    char buf[16];
    snprintf(buf, sizeof(buf), "%d", count);
    write_file_content(FAILURE_COUNT_FILE, buf);
}

int main(int argc, char** argv) {
    signal(SIGTERM, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, SIG_IGN);

    LOGI("===== SECURITY VERIFICATION STARTED =====");

    int failure_count = read_failure_count();
    if (failure_count >= MAX_FAILURES) {
        LOGW("⚠ Boot failure count exceeded (%d). Skipping security check to allow recovery.", failure_count);
        LOGI("===== RECOVERY MODE: Booting normally. =====");
        write_failure_count(0);
        return 0;
    }

    int sku_valid = 0;
    char* sku = read_property("ro.boot.product.hardware.sku");
    if (!sku || strlen(sku) == 0) {
        LOGE("✗ Hardware SKU property is empty or missing.");
    } else {
        if (strcmp(sku, "lime") == 0 || strcmp(sku, "lemon") == 0 ||
            strcmp(sku, "pomelo") == 0 || strcmp(sku, "citrus") == 0) {
            LOGI("✓ Hardware SKU verified: %s", sku);
            sku_valid = 1;
        } else {
            LOGE("✗ Invalid Hardware SKU: %s (Expected: lime, lemon, pomelo, or citrus)", sku);
        }
    }
    free(sku);

    int dev_valid = 0;
    char* dev = read_property("ro.mrt.developer");
    if (!dev || strlen(dev) == 0) {
        LOGE("✗ ro.mrt.developer property is empty or missing.");
    } else if (strcmp(dev, "AnGgIt86") == 0) {
        LOGI("✓ Developer property verified: %s", dev);
        dev_valid = 1;
    } else {
        LOGE("✗ Invalid developer property: %s (Expected: AnGgIt86)", dev);
    }
    free(dev);

    LOGI("Waiting for config file to be accessible...");
    char* resolved_path = NULL;
    int max_wait = 60;
    int waited = 0;
    while (waited < max_wait) {
        resolved_path = resolve_file_path(CONFIG_FILE);
        if (resolved_path) {
            LOGI("✓ Config file resolved to: %s", resolved_path);
            break;
        }
        sleep(2);
        waited += 2;
    }
    if (!resolved_path) {
        LOGE("✗ %s still not found after %ds. Proceeding cautiously.", CONFIG_FILE, max_wait);
    }

    int integrity_passed = 0;
    // Perbaikan: actual_file mengambil alih resolved_path, tidak ada double free
    char* actual_file = NULL;
    if (resolved_path) {
        actual_file = resolved_path;   // ambil alih pointer
    } else {
        actual_file = strdup(CONFIG_FILE);
    }

    if (access(actual_file, F_OK) == 0) {
        char* hash = sha256_file(actual_file);
        if (hash) {
            if (strcmp(hash, EXPECTED_HASH) == 0) {
                if (sku_valid && dev_valid) {
                    integrity_passed = 1;
                    LOGI("✓ Integrity OK (hash, SKU, and developer validated).");
                } else {
                    LOGE("✗ SKU or Developer validation failed.");
                }
            } else {
                LOGE("✗ Hash mismatch! Expected: %s, got: %s", EXPECTED_HASH, hash);
            }
            free(hash);
        } else {
            LOGE("✗ Failed to compute hash for %s", actual_file);
        }
    } else {
        LOGE("✗ Config file MISSING.");
    }

    // Hanya free actual_file (resolved_path sudah sama, tidak perlu free lagi)
    if (actual_file) {
        free(actual_file);
    }

    if (!integrity_passed) {
        failure_count++;
        write_failure_count(failure_count);
        LOGW("⚠ Failure count incremented to %d", failure_count);

        char* debuggable = read_property("ro.debuggable");
        if (debuggable && strcmp(debuggable, "1") == 0) {
            LOGW("⚠ Debuggable device detected! Still executing security.");
        }
        free(debuggable);

        sleep(5);

        if (is_package_installed(SECURITY_PKG)) {
            LOGI("Package %s installed. Launching activity...", SECURITY_PKG);
            launch_security_activity();
            sleep(5);
        } else {
            LOGE("MRT security app NOT installed (exact match). Shutting down immediately.");
            force_shutdown();
            return 0;
        }

        LOGI("Security trigger complete. Shutting down system.");
        force_shutdown();
        return 0;
    } else {
        write_failure_count(0);
        LOGI("===== INTEGRITY PASSED. Booting normally. =====");
        return 0;
    }
}
