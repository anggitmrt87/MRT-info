# MRT Reborn – HyperReborn

> **Version 2.3** – Stabil, deteksi APatch, dan **hash mrt_loader otomatis diperbarui** saat build.

MRT Reborn adalah proyek Android native yang terdiri dari **shared library** (`libmrtreborn.so`) untuk mengumpulkan dan menampilkan informasi sistem perangkat, serta **security checker** (`mrt_security`) untuk memverifikasi integritas boot dan perangkat. Library ini dirancang untuk dijalankan pada saat inisialisasi aplikasi atau proses Android, memberikan gambaran cepat tentang kondisi perangkat tanpa alat tambahan.

---

## 📋 Daftar Isi

- [Fitur](#fitur)
- [Persyaratan](#persyaratan)
- [Struktur Proyek](#struktur-proyek)
- [Cara Build](#cara-build)
  - [Build Lokal dengan NDK](#build-lokal-dengan-ndk)
  - [Build dengan GitHub Actions](#build-dengan-github-actions)
- [Cara Deploy ke Perangkat](#cara-deploy-ke-perangkat)
- [Menjalankan Komponen](#menjalankan-komponen)
- [Mekanisme Auto-Update Hash](#mekanisme-auto-update-hash)
- [Konfigurasi Security Checker](#konfigurasi-security-checker)
- [Logging dan Output](#logging-dan-output)
- [Troubleshooting](#troubleshooting)
- [Lisensi](#lisensi)
- [Kontribusi](#kontribusi)

---

## ✨ Fitur

### Library (`libmrtreborn.so`)
- 🧠 **Deteksi perangkat** – Nama pasar, kode perangkat, dan model.
- 🔒 **Status bootloader** – Mendeteksi locked/unlocked dari berbagai properti dan cmdline.
- 📱 **Status root** – Mendeteksi keberadaan `su`, Magisk, KernelSU, dan **APatch**.
- 🔧 **Recovery** – Mendeteksi keberadaan TWRP dan OrangeFox.
- 🧬 **Informasi ROM** – Menampilkan versi incremental dan display ID.
- 🛡️ **Keamanan** – Status SELinux dan AVB (dm-verity).
- 🖥️ **Kernel & arsitektur** – Versi kernel dan arsitektur CPU.
- 📝 **Logging** – Output ke logcat (tag `MRTReborn`) dan file di `/data/local/tmp/mrt_reborn.log` dengan rotasi otomatis (1 MB).
- ⚙️ **Otomatis** – Dijalankan saat library dimuat (`__attribute__((constructor))`).

### Security Checker (`mrt_security`)
- ✅ **Verifikasi integritas** – Memeriksa hash SHA256 dari `mrt_loader` (hardcoded pada saat build).
- ✅ **Validasi hardware SKU** – Hanya mengizinkan SKU tertentu (`lime`, `lemon`, `pomelo`, `citrus`).
- ✅ **Validasi developer property** – Memeriksa `ro.mrt.developer` (harus `AnGgIt86`).
- 🛡️ **Bootloop protection** – Menghitung kegagalan; setelah 3 kali, boot normal (recovery mode).
- 📦 **Integrasi dengan aplikasi keamanan** – Jika gagal, meluncurkan aktivitas `com.chime.updatechecker.SecActivity` atau shutdown.
- 🔄 **SHA256 internal** – Tidak bergantung pada perintah eksternal `sha256sum` di perangkat target.

---

## 📦 Persyaratan

- **Android NDK** (r23+ direkomendasikan) – untuk kompilasi native.
- **Make** – untuk menjalankan `Makefile`.
- **ADB** – untuk men-deploy ke perangkat (opsional, untuk pengujian).
- **sha256sum** – tersedia di Linux/macOS (atau WSL/Git Bash di Windows) untuk menghitung hash saat build.
- **GitHub Actions** (opsional) – jika ingin build otomatis di cloud.

---

## 📁 Struktur Proyek

