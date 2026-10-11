// SPDX-License-Identifier: GPL-2.0
/*
 * micharge_monitor - Watch USB charger plug/unplug events
 *
 * Polls /sys/class/power_supply/usb/present and updates the
 * vendor.micharge.present property. init reacts to that property
 * to start/stop the heavy mrt_micharge service.
 *
 * Runs always. Extremely light: one read + one property compare
 * every 2 seconds.
 */

#define LOG_TAG "MrtMiChargeMon"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <syslog.h>
#include <cutils/properties.h>

#define PATH_PRESENT  "/sys/class/power_supply/usb/present"
#define PROP_PRESENT  "vendor.micharge.present"
#define POLL_SEC      2

static volatile int g_running = 1;

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

static int read_present(void) {
    int fd;
    char buf[16];
    ssize_t n;

    fd = open(PATH_PRESENT, O_RDONLY);
    if (fd < 0) return -1;

    n = read(fd, buf, sizeof(buf) - 1);
    close(fd);

    if (n <= 0) return -1;
    buf[n] = '\0';
    return atoi(buf);
}

static void update_property(void) {
    int present = read_present();
    char cur[PROP_VALUE_MAX];

    if (present < 0) return;    /* file not there yet */

    property_get(PROP_PRESENT, cur, "0");
    int cur_val = atoi(cur);

    if (cur_val != present) {
        property_set(PROP_PRESENT, present ? "1" : "0");
        syslog(LOG_INFO, "charger present=%d", present);
    }
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);

    openlog(LOG_TAG, LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_INFO, "monitor started");

    while (g_running) {
        update_property();

        /* sleep(POLL_SEC) but wake early on signal */
        if (sleep(POLL_SEC) > 0 && !g_running)
            break;
    }

    syslog(LOG_INFO, "monitor stopped");
    closelog();
    return 0;
}
