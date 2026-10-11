// SPDX-License-Identifier: GPL-2.0
/*
 * mrt_micharge - MIUI fast charge detection bypass
 *
 * Started by init when charger is plugged, stopped when unplugged.
 * Reads charger state from Qualcomm sysfs and broadcasts
 * miui.intent.action.ACTION_QUICK_CHARGE_TYPE via /system/bin/am.
 */

#define LOG_TAG "MrtMiCharge"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <syslog.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <cutils/properties.h>

#define PATH_REAL_TYPE   "/sys/class/power_supply/usb/real_type"
#define PATH_TYPE        "/sys/class/power_supply/usb/type"
#define PATH_VOLT_MAX    "/sys/class/power_supply/usb/voltage_max"
#define PATH_PRESENT     "/sys/class/power_supply/usb/present"
#define PATH_CHARGE_TYPE "/sys/class/power_supply/battery/charge_type"

#define POLL_INTERVAL_SEC 2

static volatile int g_running = 1;

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

static int read_sysfs(const char *path, char *buf, size_t size) {
    int fd;
    ssize_t n;
    size_t i;

    if (!path || !buf || size == 0) return -1;

    fd = open(path, O_RDONLY);
    if (fd < 0) return -1;

    n = read(fd, buf, size - 1);
    close(fd);

    if (n <= 0) return -1;

    buf[n] = '\0';
    for (i = 0; i < (size_t)n; i++) {
        if (buf[i] == '\n' || buf[i] == '\r' ||
            buf[i] == ' '  || buf[i] == '\t') {
            buf[i] = '\0';
            break;
        }
    }
    return 0;
}

static int read_int(const char *path, int default_value) {
    char buf[32];
    if (read_sysfs(path, buf, sizeof(buf)) != 0)
        return default_value;
    return atoi(buf);
}

static int map_to_quick_charge_type(const char *real_type,
                                    const char *batt_type,
                                    int present,
                                    int volt_max)
{
    if (!present) return 0;

    if (strstr(real_type, "HVDCP_3P5"))                              return 3;
    if (strstr(real_type, "HVDCP_3"))                                return 3;
    if (strstr(real_type, "HVDCP"))                                  return 2;
    if (strstr(real_type, "PD_PPS") || strstr(real_type, "PPS"))     return 3;
    if (strstr(real_type, "PD"))                                     return 2;
    if (strstr(real_type, "VOOC") || strstr(real_type, "WARP") ||
        strstr(real_type, "SUPERVOOC"))                              return 3;
    if (strstr(real_type, "DCP"))                                    return 1;
    if (strstr(real_type, "CDP"))                                    return 1;
    if (strstr(real_type, "SDP"))                                    return 1;
    if (strstr(real_type, "FLOAT"))                                  return 0;

    if (strcmp(batt_type, "Fast")  == 0 ||
        strcmp(batt_type, "TURBO") == 0 ||
        strcmp(batt_type, "Turbo") == 0)                             return 3;
    if (strcmp(batt_type, "Normal") == 0)                            return 1;

    if (volt_max >= 9000000)                                         return 3;
    if (volt_max >= 6000000)                                         return 2;

    return 0;
}

static int power_from_qct(int qct) {
    switch (qct) {
        case 3:  return 33;
        case 2:  return 18;
        case 1:  return 10;
        default: return 0;
    }
}

static int boot_completed(void) {
    char buf[PROP_VALUE_MAX];
    property_get("sys.boot_completed", buf, "0");
    return buf[0] == '1';
}

static void send_broadcast(int qct, const char *real_type,
                           const char *batt_type, int volt_max)
{
    pid_t pid;
    int status = 0;
    char qct_str[12];
    char power_str[12];
    int power = power_from_qct(qct);

    snprintf(qct_str, sizeof(qct_str), "%d", qct);
    snprintf(power_str, sizeof(power_str), "%d", power);

    syslog(LOG_INFO,
        "broadcast: qct=%d power=%dW (real=%s batt=%s volt=%d)",
        qct, power, real_type, batt_type, volt_max);

    pid = fork();
    if (pid < 0) {
        syslog(LOG_ERR, "fork failed: %s", strerror(errno));
        return;
    }

    if (pid == 0) {
        int fd = open("/dev/null", O_RDWR);
        if (fd >= 0) {
            dup2(fd, STDIN_FILENO);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            if (fd > 2) close(fd);
        }

        execl("/system/bin/am", "am", "broadcast",
              "-a", "miui.intent.action.ACTION_QUICK_CHARGE_TYPE",
              "--ei", "miui.intent.extra.quick_charge_type", qct_str,
              "--ei", "miui.intent.extra.POWER_MAX", power_str,
              (char *)NULL);

        _exit(127);
    }

    if (waitpid(pid, &status, 0) < 0) {
        syslog(LOG_WARNING, "waitpid failed: %s", strerror(errno));
        return;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        syslog(LOG_WARNING, "am broadcast failed (status=0x%x)", status);
    }
}

int main(int argc, char **argv) {
    int last_qct = -2;
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 ||
            strcmp(argv[i], "--help") == 0) {
            printf("Usage: %s [-h|--help]\n", argv[0]);
            return 0;
        }
    }

    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);
    signal(SIGCHLD, SIG_IGN);

    openlog(LOG_TAG, LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_INFO, "service started");

    while (g_running) {
        char real_type[32] = {0};
        char batt_type[32] = {0};
        int present, volt_max, qct;

        read_sysfs(PATH_REAL_TYPE,   real_type, sizeof(real_type));
        read_sysfs(PATH_CHARGE_TYPE, batt_type, sizeof(batt_type));
        present  = read_int(PATH_PRESENT,  0);
        volt_max = read_int(PATH_VOLT_MAX, 0);

        qct = map_to_quick_charge_type(real_type, batt_type,
                                       present, volt_max);

        if (qct != last_qct) {
            if (boot_completed()) {
                syslog(LOG_INFO,
                    "state: present=%d real_type='%s' batt_type='%s' "
                    "volt_max=%d -> qct=%d",
                    present, real_type, batt_type, volt_max, qct);
                send_broadcast(qct, real_type, batt_type, volt_max);
                last_qct = qct;
            } else {
                /* hold: don't update last_qct, retry next poll */
                syslog(LOG_INFO, "waiting for boot_completed...");
            }
        }

        if (sleep(POLL_INTERVAL_SEC) > 0 && !g_running)
            break;
    }

    /* On shutdown (unplugged / stop), broadcast qct=0 if we were charging */
    if (last_qct > 0) {
        syslog(LOG_INFO, "shutting down: broadcasting qct=0");
        send_broadcast(0, "", "", 0);
    }

    syslog(LOG_INFO, "service stopped");
    closelog();
    return 0;
}
