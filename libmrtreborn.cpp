// lib_mrtreborn.cpp
// Version 2.2 – stabil, konsisten, log hanya banner
#include <android/log.h>
#include <unistd.h>
#include <chrono>
#include <fstream>
#include <cstring>
#include <dirent.h>
#include <sys/utsname.h>
#include <cstdio>
#include <ctime>
#include <sys/system_properties.h>
#include <sys/stat.h>
#include <string>

#define LOG_TAG "MRTReborn"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ---------- Helper: baca properti (kembalikan std::string) ----------
static std::string get_prop(const char* key, const char* default_val = "unknown") {
    char value[PROP_VALUE_MAX];
    int len = __system_property_get(key, value);
    if (len > 0 && value[0] != '\0') {
        return std::string(value);
    }
    return std::string(default_val);
}

// ---------- Device info (marketname prioritas) ----------
static const char* get_device_info() {
    static char buf[256];
    std::string market = get_prop("ro.product.marketname", "");
    std::string manufacturer = get_prop("ro.product.manufacturer", "");
    std::string model = get_prop("ro.product.model", "");
    std::string device = get_prop("ro.product.device", "");

    std::string display_name;
    if (!market.empty() && market != "unknown") {
        display_name = market;
    } else if (!manufacturer.empty() && manufacturer != "unknown") {
        display_name = manufacturer + " " + model;
    } else {
        display_name = model;
    }

    snprintf(buf, sizeof(buf), "%s (%s/%s)",
             display_name.c_str(), device.c_str(), model.c_str());
    return buf;
}

// ---------- Bootloader ----------
static const char* get_bootloader_status() {
    static char buf[32];
    std::string locked = get_prop("ro.boot.flash.locked", "");
    if (locked == "0") { snprintf(buf, sizeof(buf), "UNLOCKED"); return buf; }
    if (locked == "1") { snprintf(buf, sizeof(buf), "LOCKED"); return buf; }

    std::string state = get_prop("ro.boot.vbmeta.device_state", "");
    if (state == "unlocked") { snprintf(buf, sizeof(buf), "UNLOCKED"); return buf; }
    if (state == "locked")   { snprintf(buf, sizeof(buf), "LOCKED"); return buf; }

    std::string vbs = get_prop("ro.boot.verifiedbootstate", "");
    if (vbs == "orange") { snprintf(buf, sizeof(buf), "UNLOCKED (orange)"); return buf; }
    if (vbs == "green")  { snprintf(buf, sizeof(buf), "LOCKED (green)"); return buf; }

    // fallback cmdline
    std::ifstream cmdline("/proc/cmdline");
    if (cmdline.is_open()) {
        std::string line;
        std::getline(cmdline, line);
        if (line.find("androidboot.flash.locked=0") != std::string::npos)
            { snprintf(buf, sizeof(buf), "UNLOCKED"); return buf; }
        if (line.find("androidboot.flash.locked=1") != std::string::npos)
            { snprintf(buf, sizeof(buf), "LOCKED"); return buf; }
        if (line.find("androidboot.verifiedbootstate=orange") != std::string::npos)
            { snprintf(buf, sizeof(buf), "UNLOCKED (orange)"); return buf; }
        if (line.find("androidboot.verifiedbootstate=green") != std::string::npos)
            { snprintf(buf, sizeof(buf), "LOCKED (green)"); return buf; }
    }
    snprintf(buf, sizeof(buf), "unknown");
    return buf;
}

// ---------- TWRP ----------
static bool has_twrp() {
    if (access("/sdcard/TWRP", F_OK) == 0) return true;
    if (access("/data/media/0/TWRP", F_OK) == 0) return true;
    if (access("/external_sd/TWRP", F_OK) == 0) return true;
    DIR* dir = opendir("/cache/recovery/");
    if (dir) {
        struct dirent* ent;
        while ((ent = readdir(dir)) != NULL) {
            if (strstr(ent->d_name, ".twrp") != NULL) {
                closedir(dir);
                return true;
            }
        }
        closedir(dir);
    }
    return false;
}

// ---------- OrangeFox ----------
static bool has_orangefox() {
    if (access("/sdcard/Fox", F_OK) == 0) return true;
    if (access("/data/media/0/Fox", F_OK) == 0) return true;
    if (access("/external_sd/Fox", F_OK) == 0) return true;
    DIR* dir = opendir("/cache/recovery/");
    if (dir) {
        struct dirent* ent;
        while ((ent = readdir(dir)) != NULL) {
            if (strstr(ent->d_name, ".fox") != NULL) {
                closedir(dir);
                return true;
            }
        }
        closedir(dir);
    }
    if (access("/system/etc/orangefox.cfg", F_OK) == 0) return true;
    return false;
}

// ---------- Magisk ----------
static bool has_magisk() {
    if (access("/sbin/.magisk", F_OK) == 0) return true;
    if (access("/data/adb/magisk", F_OK) == 0) return true;
    if (access("/magisk", F_OK) == 0) return true;
    if (access("/data/adb/modules", F_OK) == 0) {
        DIR* dir = opendir("/data/adb/modules");
        if (dir) {
            struct dirent* ent;
            while ((ent = readdir(dir)) != NULL) {
                if (strstr(ent->d_name, ".magisk") != NULL) {
                    closedir(dir);
                    return true;
                }
            }
            closedir(dir);
        }
    }
    std::ifstream proc("/proc/self/status");
    std::string line;
    while (std::getline(proc, line)) {
        if (line.find("magisk") != std::string::npos) return true;
    }
    return false;
}

// ---------- KernelSU ----------
static bool has_kernelsu() {
    if (access("/data/adb/ksu", F_OK) == 0) return true;
    if (access("/proc/ksu", F_OK) == 0) return true;
    struct utsname buf;
    if (uname(&buf) == 0) {
        if (strstr(buf.version, "KernelSU") != NULL) return true;
        if (strstr(buf.release, "kernelsu") != NULL) return true;
    }
    if (access("/data/adb/ksu/ksud", F_OK) == 0) return true;
    std::ifstream prop_file("/default.prop");
    if (prop_file.is_open()) {
        std::string line;
        while (std::getline(prop_file, line)) {
            if (line.find("ro.kernel.kernelsu") != std::string::npos) return true;
        }
    }
    return false;
}

// ---------- Root ----------
static bool is_rooted() {
    const char* su_paths[] = {"/system/bin/su", "/system/xbin/su", "/sbin/su",
                              "/su/bin/su", "/data/local/xbin/su", "/data/local/bin/su", NULL};
    for (int i = 0; su_paths[i] != NULL; ++i) {
        if (access(su_paths[i], F_OK) == 0) return true;
    }
    return has_magisk() || has_kernelsu();
}

// ---------- Custom ROM ----------
static const char* get_custom_rom() {
    static char buf[128];
    std::string incremental = get_prop("ro.build.version.incremental", "");
    std::string display = get_prop("ro.build.display.id", "");

    // Jika keduanya tersedia, gabungkan
    if (!incremental.empty() && incremental != "unknown" &&
        !display.empty() && display != "unknown") {
        snprintf(buf, sizeof(buf), "%s (%s)", incremental.c_str(), display.c_str());
        return buf;
    }

    // Fallback ke ro.modversion
    std::string modver = get_prop("ro.modversion", "");
    if (!modver.empty() && modver != "unknown") {
        snprintf(buf, sizeof(buf), "%s", modver.c_str());
        return buf;
    }

    // Fallback terakhir: hanya display id
    if (!display.empty() && display != "unknown") {
        snprintf(buf, sizeof(buf), "%s", display.c_str());
        return buf;
    }

    snprintf(buf, sizeof(buf), "unknown");
    return buf;
}

// ---------- AVB ----------
static const char* get_avb_status() {
    static char buf[32];
    std::string verity = get_prop("ro.boot.veritymode", "");
    if (verity == "enforcing") { snprintf(buf, sizeof(buf), "enforcing (ON)"); return buf; }
    if (verity == "logging")   { snprintf(buf, sizeof(buf), "logging"); return buf; }
    if (verity == "off")       { snprintf(buf, sizeof(buf), "off (DISABLED)"); return buf; }

    std::string dm = get_prop("ro.boot.dmverity", "");
    if (dm == "enforcing") { snprintf(buf, sizeof(buf), "enforcing (ON)"); return buf; }
    if (dm == "off")       { snprintf(buf, sizeof(buf), "off (DISABLED)"); return buf; }

    snprintf(buf, sizeof(buf), "unknown");
    return buf;
}

// ---------- Kernel & arch ----------
static const char* get_kernel_and_arch() {
    static char buf[128];
    struct utsname u;
    if (uname(&u) == 0) {
        snprintf(buf, sizeof(buf), "%s (%s)", u.release, u.machine);
        return buf;
    }
    snprintf(buf, sizeof(buf), "unknown");
    return buf;
}

// ---------- SELinux ----------
static const char* get_selinux_status() {
    static char buf[16];
    std::ifstream f("/sys/fs/selinux/enforce");
    if (!f.is_open()) { snprintf(buf, sizeof(buf), "unknown"); return buf; }
    int val; f >> val;
    snprintf(buf, sizeof(buf), "%s", val == 1 ? "Enforcing" : "Permissive");
    return buf;
}

// ---------- Rotasi log (jika > 1 MB) ----------
static void rotate_log_if_needed(const char* path) {
    struct stat st;
    if (stat(path, &st) == 0 && st.st_size > 1024 * 1024) {
        std::string old = std::string(path) + ".old";
        rename(path, old.c_str());
    }
}

// ---------- Tulis banner ke file (timpa, tanpa summary) ----------
static void write_to_file() {
    const char* log_path = "/data/local/tmp/mrt_reborn.log";
    rotate_log_if_needed(log_path);

    std::ofstream logfile(log_path, std::ios::out | std::ios::trunc);
    if (!logfile.is_open()) return;

    logfile << "\n";
    logfile << "  ╔═════════════════════════════════════════════════════════════╗\n";
    logfile << "  ║   ✦  M•R•T Project™  ✦  v2.2  ✦  HyperReborn  ✦    ║\n";
    logfile << "  ║  ──────────────────────────────────────────────────────────────\n";

    char line[256];
    snprintf(line, sizeof(line), "  ║  Device        : %-47s ║", get_device_info());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  Kernel/Arch   : %-47s ║", get_kernel_and_arch());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  Bootloader    : %-47s ║", get_bootloader_status());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  Custom ROM    : %-47s ║", get_custom_rom());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  Root Status   : %-47s ║", is_rooted() ? "ROOTED" : "NOT ROOTED");
    logfile << line << "\n";

    logfile << "  ║  ────────────  Root Methods  ────────────\n";
    snprintf(line, sizeof(line), "  ║  Magisk        : %-47s ║", has_magisk() ? "✅ DETECTED" : "❌ NOT FOUND");
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  KernelSU      : %-47s ║", has_kernelsu() ? "✅ DETECTED" : "❌ NOT FOUND");
    logfile << line << "\n";

    logfile << "  ║  ────────────  Recoveries  ──────────────────\n";
    snprintf(line, sizeof(line), "  ║  TWRP          : %-47s ║", has_twrp() ? "✅ DETECTED" : "❌ NOT FOUND");
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  OrangeFox     : %-47s ║", has_orangefox() ? "✅ DETECTED" : "❌ NOT FOUND");
    logfile << line << "\n";

    logfile << "  ║  ──────────────────────────────────────────────────────────────\n";
    snprintf(line, sizeof(line), "  ║  SELinux       : %-47s ║", get_selinux_status());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  AVB (dm-verity): %-46s ║", get_avb_status());
    logfile << line << "\n";
    snprintf(line, sizeof(line), "  ║  PID           : %-47d ║", getpid());
    logfile << line << "\n";

    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    snprintf(line, sizeof(line), "  ║  Load time     : %-47lld ms ║", (long long)ms);
    logfile << line << "\n";

    logfile << "  ║  ──────────────────────────────────────────────────────────────\n";
    logfile << "  ║  [✓] Library validated by MRT Project™.\n";
    logfile << "  ║  [✓] Booting sequence will continue normally.\n";
    logfile << "  ╚═════════════════════════════════════════════════════════════╝\n";
    logfile << "\n";

    // Summary sudah dihapus
    logfile.close();
}

// ---------- Banner ke logcat ----------
static void print_banner_to_logcat() {
    char line[256];
    LOGI(" ");
    LOGI("  ╔═════════════════════════════════════════════════════════════╗");
    LOGI("  ║   ✦  M•R•T Project™  ✦  v2.2  ✦  HyperReborn  ✦    ║");
    LOGI("  ║  ──────────────────────────────────────────────────────────────");
    snprintf(line, sizeof(line), "  ║  Device        : %-47s ║", get_device_info());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  Kernel/Arch   : %-47s ║", get_kernel_and_arch());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  Bootloader    : %-47s ║", get_bootloader_status());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  Custom ROM    : %-47s ║", get_custom_rom());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  Root Status   : %-47s ║", is_rooted() ? "ROOTED" : "NOT ROOTED");
    LOGI("%s", line);
    LOGI("  ║  ────────────  Root Methods  ────────────");
    snprintf(line, sizeof(line), "  ║  Magisk        : %-47s ║", has_magisk() ? "✅ DETECTED" : "❌ NOT FOUND");
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  KernelSU      : %-47s ║", has_kernelsu() ? "✅ DETECTED" : "❌ NOT FOUND");
    LOGI("%s", line);
    LOGI("  ║  ────────────  Recoveries  ──────────────────");
    snprintf(line, sizeof(line), "  ║  TWRP          : %-47s ║", has_twrp() ? "✅ DETECTED" : "❌ NOT FOUND");
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  OrangeFox     : %-47s ║", has_orangefox() ? "✅ DETECTED" : "❌ NOT FOUND");
    LOGI("%s", line);
    LOGI("  ║  ──────────────────────────────────────────────────────────────");
    snprintf(line, sizeof(line), "  ║  SELinux       : %-47s ║", get_selinux_status());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  AVB (dm-verity): %-46s ║", get_avb_status());
    LOGI("%s", line);
    snprintf(line, sizeof(line), "  ║  PID           : %-47d ║", getpid());
    LOGI("%s", line);
    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    snprintf(line, sizeof(line), "  ║  Load time     : %-47lld ms ║", (long long)ms);
    LOGI("%s", line);
    LOGI("  ║  ──────────────────────────────────────────────────────────────");
    LOGI("  ║  [✓] Library validated by MRT Project™.");
    LOGI("  ║  [✓] Booting sequence will continue normally.");
    LOGI("  ╚═════════════════════════════════════════════════════════════╝");
    LOGI(" ");
}

// ---------- Constructor ----------
__attribute__((constructor))
static void mrt_init() {
    try {
        LOGI("=== MRT Reborn v2.2 constructor started ===");
        print_banner_to_logcat();
        write_to_file();
        LOGI("=== MRT Reborn constructor finished ===");
    } catch (...) {
        LOGE("Exception caught in constructor");
    }
}

extern "C" void mrt_dummy() {}