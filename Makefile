# =============================================================================
# Makefile untuk MRT Reborn
# Mendukung multiple arsitektur Android (arm64-v8a, armeabi-v7a, x86_64, x86)
# =============================================================================

# ------------------------------
# Konfigurasi default
# ------------------------------
NDK_PATH    ?= /opt/android-ndk
API_LEVEL   ?= 21
TARGET_ARCH ?= arm64-v8a

# ------------------------------
# Deteksi toolchain berdasarkan TARGET_ARCH
# ------------------------------
ifeq ($(TARGET_ARCH), arm64-v8a)
    TRIPLE        = aarch64-linux-android
    CLANG_PREFIX  = aarch64-linux-android$(API_LEVEL)
    LIB_ARCH      = arm64-v8a
else ifeq ($(TARGET_ARCH), armeabi-v7a)
    TRIPLE        = armv7a-linux-androideabi
    CLANG_PREFIX  = armv7a-linux-androideabi$(API_LEVEL)
    LIB_ARCH      = armeabi-v7a
else ifeq ($(TARGET_ARCH), x86_64)
    TRIPLE        = x86_64-linux-android
    CLANG_PREFIX  = x86_64-linux-android$(API_LEVEL)
    LIB_ARCH      = x86_64
else ifeq ($(TARGET_ARCH), x86)
    TRIPLE        = i686-linux-android
    CLANG_PREFIX  = i686-linux-android$(API_LEVEL)
    LIB_ARCH      = x86
else
    $(error Unsupported TARGET_ARCH: $(TARGET_ARCH))
endif

# Lokasi toolchain (LLVM)
TOOLCHAIN_DIR = $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64
CC            = $(TOOLCHAIN_DIR)/bin/$(CLANG_PREFIX)-clang
CXX           = $(TOOLCHAIN_DIR)/bin/$(CLANG_PREFIX)-clang++
LD            = $(TOOLCHAIN_DIR)/bin/ld.lld
AR            = $(TOOLCHAIN_DIR)/bin/llvm-ar

# ------------------------------
# Flags kompilasi dan linking
# ------------------------------
COMMON_FLAGS = -fPIC -Wall -O2 -DANDROID
CXX_FLAGS    = $(COMMON_FLAGS) -std=c++17
C_FLAGS      = $(COMMON_FLAGS) -std=c11

# Linker flags: gunakan libc++_static untuk menghindari dependensi runtime
LDFLAGS      = -L$(TOOLCHAIN_DIR)/sysroot/usr/lib/$(TRIPLE)/$(API_LEVEL) \
               -lstdc++ -ldl -llog

# ------------------------------
# Nama target
# ------------------------------
LIB_NAME     = libmrtreborn.so
LOADER_NAME  = mrt_loader

# Path tempat library akan diletakkan di perangkat (hardcode di loader)
LIB_INSTALL_PATH = /system/$(TARGET_ARCH)/$(LIB_NAME)

# ------------------------------
# Aturan build
# ------------------------------
all: $(LIB_NAME) $(LOADER_NAME)

$(LIB_NAME): libmrtreborn.cpp
	$(CXX) $(CXX_FLAGS) -shared $< -o $@ $(LDFLAGS)

$(LOADER_NAME): mrt_loader.c
	$(CC) $(C_FLAGS) -DLIB_PATH=\"$(LIB_INSTALL_PATH)\" $< -o $@ $(LDFLAGS)

# ------------------------------
# Pembersihan
# ------------------------------
clean:
	rm -f $(LIB_NAME) $(LOADER_NAME)

# ------------------------------
# Instalasi ke perangkat (memerlukan adb)
# ------------------------------
push: $(LIB_NAME) $(LOADER_NAME)
	adb push $(LIB_NAME) $(LIB_INSTALL_PATH)
	adb push $(LOADER_NAME) /data/local/tmp/
	adb shell chmod 755 /data/local/tmp/$(LOADER_NAME)

# ------------------------------
# Menjalankan loader di perangkat
# ------------------------------
run: push
	adb shell /data/local/tmp/$(LOADER_NAME)

# ------------------------------
# Menampilkan logcat
# ------------------------------
logcat:
	adb logcat -s MRTReborn MRTLoader

.PHONY: all clean push run logcat