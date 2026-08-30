# MRT Reborn – HyperReborn

> **Version 2.2** – Stabil, konsisten, dan hanya menampilkan banner informasi sistem.

MRT Reborn adalah *shared library* yang dimuat pada saat inisialisasi aplikasi atau proses Android. Library ini secara otomatis mengumpulkan informasi penting tentang perangkat (device, kernel, bootloader, status root, recovery, dll.) dan menampilkannya dalam format banner yang rapi ke **logcat** dan file **/data/local/tmp/mrt_reborn.log**.

Proyek ini dirancang untuk **analisis cepat** kondisi perangkat Android tanpa perlu alat tambahan. Cocok untuk pengembang ROM, tester, atau peneliti keamanan.

---

## ✨ Fitur

- 🧠 **Deteksi perangkat** – Menampilkan nama pasar, kode perangkat, dan model.
- 🔒 **Status bootloader** – Mendeteksi locked/unlocked dari berbagai properti dan cmdline.
- 📱 **Status root** – Mendeteksi keberadaan `su`, Magisk, dan KernelSU.
- 🔧 **Recovery** – Mendeteksi keberadaan TWRP dan OrangeFox.
- 🧬 **Informasi ROM** – Menampilkan versi incremental dan display ID.
- 🛡️ **Keamanan** – Status SELinux dan AVB (dm-verity).
- 🖥️ **Kernel & arsitektur** – Menampilkan versi kernel dan arsitektur CPU.
- 📝 **Logging** – Output ke logcat (tag `MRTReborn`) dan file log di `/data/local/tmp/` dengan rotasi otomatis (1 MB).
- ⚙️ **Otomatis** – Dijalankan saat library dimuat (`__attribute__((constructor))`).

---

## 📦 Persyaratan

- **Android NDK** (r23+ direkomendasikan) – untuk kompilasi native.
- **Make** – untuk menjalankan `Makefile`.
- **ADB** – untuk men-deploy ke perangkat (opsional, hanya untuk pengujian).
- **GitHub Actions** (opsional) – jika ingin build otomatis di cloud.

---

## 🚀 Cara Build

### 1. Build Lokal dengan NDK

Pastikan variabel `NDK_PATH` menunjuk ke direktori NDK yang benar.

```bash
# Build untuk arm64-v8a (default)
make

# Build untuk arsitektur lain
make TARGET_ARCH=armeabi-v7a
make TARGET_ARCH=x86_64
make TARGET_ARCH=x86
