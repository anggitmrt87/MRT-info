# =============================================================================
# Makefile untuk MRT Reborn
# Mendukung multiple arsitektur Android (arm64-v8a, armeabi-v7a)
# =============================================================================

# ------------------------------
# Konfigurasi default
# ------------------------------
NDK_PATH    ?= /opt/android-ndk
API_LEVEL   ?= 21
TARGET_ARCH ?= arm64-v8a

# ------------------------------
# Nama target
# ------------------------------
LIB_NAME     = libmrtreborn.so
LOADER_NAME  = mrt_loader
SECURITY_NAME = mrt_security

# ------------------------------
# Deteksi toolchain berdasarkan TARGET_ARCH
# ------------------------------
ifeq ($(TARGET_ARCH), arm64-v8a)
    TRIPLE        = aarch64-linux-android
    CLANG_PREFIX  = aarch64-linux-android$(API_LEVEL)
    LIB_ARCH      = arm64-v8a
    LIB_INSTALL_PATH = /system/lib64/$(LIB_NAME)
else ifeq ($(TARGET_ARCH), armeabi-v7a)
    TRIPLE        = armv7a-linux-androideabi
    CLANG_PREFIX  = armv7a-linux-androideabi$(API_LEVEL)
    LIB_ARCH      = armeabi-v7a
    LIB_INSTALL_PATH = /system/lib/$(LIB_NAME)
else
    $(error Unsupported TARGET_ARCH: $(TARGET_ARCH))
endif

TOOLCHAIN_DIR = $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64
CC            = $(TOOLCHAIN_DIR)/bin/$(CLANG_PREFIX)-clang
CXX           = $(TOOLCHAIN_DIR)/bin/$(CLANG_PREFIX)-clang++
LD            = $(TOOLCHAIN_DIR)/bin/ld.lld
AR            = $(TOOLCHAIN_DIR)/bin/llvm-ar

COMMON_FLAGS = -fPIC -Wall -O2 -DANDROID
CXX_FLAGS    = $(COMMON_FLAGS) -std=c++17
C_FLAGS      = $(COMMON_FLAGS) -std=c11

LDFLAGS      = -L$(TOOLCHAIN_DIR)/sysroot/usr/lib/$(TRIPLE)/$(API_LEVEL) \
               -lstdc++ -ldl -llog

# ------------------------------
# Aturan build
# ------------------------------
all: $(LIB_NAME) $(LOADER_NAME) $(SECURITY_NAME)

$(LIB_NAME): libmrtreborn.cpp
	$(CXX) $(CXX_FLAGS) -shared $< -o $@ $(LDFLAGS)

$(LOADER_NAME): mrt_loader.c
	$(CC) $(C_FLAGS) -DLIB_PATH=\"$(LIB_INSTALL_PATH)\" $< -o $@ $(LDFLAGS)

# ============================================================
# Security checker: hash dari mrt_loader dihitung otomatis
# Build dynamic (tanpa -static) agar dapat link ke liblog
# ============================================================
$(SECURITY_NAME): mrt_security.c sha256.c $(LOADER_NAME)
	@echo "Computing SHA256 hash of $(LOADER_NAME)..."
	HASH=$$(sha256sum $(LOADER_NAME) | cut -d' ' -f1); \
	echo "Hash: $$HASH"; \
	$(CC) $(C_FLAGS) -DEXPECTED_HASH=\"$$HASH\" mrt_security.c sha256.c -o $@ $(LDFLAGS)

# ------------------------------
# Pembersihan
# ------------------------------
clean:
	rm -f $(LIB_NAME) $(LOADER_NAME) $(SECURITY_NAME)

# ------------------------------
# Instalasi ke perangkat (memerlukan adb)
# ------------------------------
push: $(LIB_NAME) $(LOADER_NAME) $(SECURITY_NAME)
	adb push $(LIB_NAME) $(LIB_INSTALL_PATH)
	adb push $(LOADER_NAME) /data/local/tmp/
	adb push $(SECURITY_NAME) /data/local/tmp/
	adb shell chmod 755 /data/local/tmp/$(LOADER_NAME)
	adb shell chmod 755 /data/local/tmp/$(SECURITY_NAME)

# ------------------------------
# Menjalankan loader
# ------------------------------
run: push
	adb shell /data/local/tmp/$(LOADER_NAME)

# ------------------------------
# Menjalankan security checker
# ------------------------------
run-security: push
	adb shell /data/local/tmp/$(SECURITY_NAME)

# ------------------------------
# Menampilkan logcat
# ------------------------------
logcat:
	adb logcat -s MRTReborn MRTLoader MRT_Security

.PHONY: all clean push run run-security logcat
