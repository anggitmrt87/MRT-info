// SPDX-License-Identifier: GPL-2.0
/*
 * micharge_monitor - Watch USB charger plug/unplug events
 *                    and force_fast_charge toggle
 *
 * Polls:
 *   /sys/class/power_supply/usb/present
 *   /sys/kernel/fast_charge/force_fast_charge
 *
 * Updates:
 *   vendor.micharge.present  -> charger physically plugged (0/1)
 *   vendor.micharge.enabled  -> force_fast_charge enabled (0/1)
 *   vendor.micharge.active   -> present && enabled (0/1)
 *
 * init reacts to vendor.micharge.active to start/stop
 * the heavy mrt_micharge service.
 *
 * Runs always. Extremely light: two reads + three property compares
 * every 2 seconds.
 *
 * ---------------------------------------------------------------------------
 *  M•R•T Project™
 *  Author : @AnGgIt86
 *  Contact: jarbull86@gmail.com
 * ---------------------------------------------------------------------------
 */

#define LOG_TAG "MrtMiChargeMon"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <syslog.h>
#include <cutils/properties.h>

#define PATH_PRESENT  "/sys/class/power_supply/usb/present"
#define PATH_FFC      "/sys/kernel/fast_charge/force_fast_charge"

#define PROP_PRESENT  "vendor.micharge.present"
#define PROP_ENABLED  "vendor.micharge.enabled"
#define PROP_ACTIVE   "vendor.micharge.active"

#define POLL_SEC      2

static volatile int g_running = 1;

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

/* Sleep function that can be interrupted by a signal */
static void interruptible_sleep(int seconds) {
    struct timespec ts;
    ts.tv_sec = seconds;
    ts.tv_nsec = 0;
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {
        if (!g_running) break;
    }
}

/*
 * Generic "read an int from sysfs, normalize to 0/1".
 * Returns:
 *   0  -> value is 0 (or equivalent)
 *   1  -> value is non-zero
 *  -1  -> file missing or unreadable
 */
static int read_sysfs_flag(const char *path) {
    int fd;
    char buf[16];
    ssize_t n;
    char *end;
    long v;

    fd = open(path, O_RDONLY);
    if (fd < 0) return -1;

    n = read(fd, buf, sizeof(buf) - 1);
    close(fd);

    if (n <= 0) return -1;
    buf[n] = '\0';

    v = strtol(buf, &end, 10);
    if (end == buf) return -1;
    return v ? 1 : 0;
}

/* Set property only if it changed. Returns 1 if changed. */
static int set_prop_if_changed(const char *key, int value) {
    char cur[PROP_VALUE_MAX];
    int cur_val;

    property_get(key, cur, "0");
    cur_val = atoi(cur) ? 1 : 0;

    if (cur_val != value) {
        property_set(key, value ? "1" : "0");
        return 1;
    }
    return 0;
}

static void update_properties(void) {
    int present = read_sysfs_flag(PATH_PRESENT);
    int enabled = read_sysfs_flag(PATH_FFC);
    int active;

    /*
     * If sysfs is missing, treat as "not present" / "not enabled"
     * so properties do not get stuck at 1.
     */
    if (present < 0) present = 0;
    if (enabled < 0) enabled = 0;

    active = (present && enabled) ? 1 : 0;

    if (set_prop_if_changed(PROP_PRESENT, present))
        syslog(LOG_INFO, "charger present=%d", present);
    if (set_prop_if_changed(PROP_ENABLED, enabled))
        syslog(LOG_INFO, "force_fast_charge enabled=%d", enabled);
    if (set_prop_if_changed(PROP_ACTIVE, active))
        syslog(LOG_INFO, "active=%d (present=%d enabled=%d)",
               active, present, enabled);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);

    openlog(LOG_TAG, LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_INFO, "monitor started (M•R•T Project™ @AnGgIt86)");

    while (g_running) {
        update_properties();

        if (!g_running) break;
        interruptible_sleep(POLL_SEC);
    }

    syslog(LOG_INFO, "monitor stopped");
    closelog();
    return 0;
}
