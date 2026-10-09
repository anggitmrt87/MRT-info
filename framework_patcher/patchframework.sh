#!/bin/bash
set -euo pipefail

# ============================================================
#  framework.jar patcher
#  - OemPorts10TUtils hooks for keystore + instrumentation
# ============================================================

dirnow=$PWD
start_time=$(date +%s)

# ---------- Logging ----------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    C_RESET=$(tput sgr0); C_BOLD=$(tput bold)
    C_RED=$(tput setaf 1); C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3)
    C_BLUE=$(tput setaf 4); C_MAGENTA=$(tput setaf 5); C_CYAN=$(tput setaf 6); C_GRAY=$(tput setaf 8)
else
    C_RESET=; C_BOLD=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_MAGENTA=; C_CYAN=; C_GRAY=
fi

STEP=0
STEP_TOTAL=10

ts()      { date '+%H:%M:%S'; }
log()     { printf '%s%s%s %s[%s]%s %s\n' "$C_GRAY" "$(ts)" "$C_RESET" "$C_BOLD$C_BLUE" "INFO" "$C_RESET" "$*"; }
ok()      { printf '%s%s%s %s[%s]%s %s%s%s\n' "$C_GRAY" "$(ts)" "$C_RESET" "$C_BOLD$C_GREEN" " OK " "$C_RESET" "$C_GREEN" "$*" "$C_RESET"; }
warn()    { printf '%s%s%s %s[%s]%s %s%s%s\n' "$C_GRAY" "$(ts)" "$C_RESET" "$C_BOLD$C_YELLOW" "WARN" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET"; }
err()     { printf '%s%s%s %s[%s]%s %s%s%s\n' "$C_GRAY" "$(ts)" "$C_RESET" "$C_BOLD$C_RED" "FAIL" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2; }
step()    { STEP=$((STEP + 1)); printf '\n%s%s▶ STEP %d/%d%s  %s%s%s\n' \
              "$C_BOLD$C_MAGENTA" "" "$STEP" "$STEP_TOTAL" "$C_RESET" \
              "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }
sub()     { printf '   %s•%s %s\n' "$C_GRAY" "$C_RESET" "$*"; }
die()     { err "$*"; printf '\n%s%s✗ build aborted at step %d/%d%s\n' \
              "$C_BOLD$C_RED" "" "$STEP" "$STEP_TOTAL" "$C_RESET" >&2; exit 1; }

on_error() {
    local code=$?
    err "command failed (exit=$code) at line ${BASH_LINENO[0]}"
    printf '%s%s✗ build aborted%s\n' "$C_BOLD$C_RED" "" "$C_RESET" >&2
    exit "$code"
}
trap on_error ERR

banner() {
    printf '%s%s\n' "$C_BOLD$C_CYAN" ""
    printf '  ┌─────────────────────────────────────────────────────┐\n'
    printf '  │           framework.jar  ·  patcher               │\n'
    printf '  │           OemPorts10TUtils  ·  hook suite         │\n'
    printf '  └─────────────────────────────────────────────────────┘%s\n' "$C_RESET"
    printf '  %sworking dir:%s %s\n' "$C_GRAY" "$C_RESET" "$dirnow"
    printf '  %sstarted at :%s %s\n\n' "$C_GRAY" "$C_RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
}

banner

# ============================================================
#  Helpers
# ============================================================

apkeditor() {
    local jarfile="$dirnow/tool/APKEditor.jar"
    local javaOpts="-Xmx4096M -Dfile.encoding=utf-8 -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true"
    java $javaOpts -jar "$jarfile" "$@"
}

expressions_fix() {
    printf '%s\n' "$1" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/\./\\./g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/\*/\\*/g' \
        -e 's/\^/\\^/g' \
        -e 's/\$/\\$/g' \
        -e 's|/|\\/|g'
}

insert_after_line() {
    local file="$1" line="$2" content="$3" tmp
    tmp=$(mktemp)
    {
        head -n "$line" "$file"
        printf '%s\n' "$content"
        tail -n +"$((line + 1))" "$file"
    } > "$tmp"
    mv "$tmp" "$file"
}

# ---------- Smali payload builders ----------

certificatechainPatch() {
    printf '    .line %s\n    invoke-static {}, Lcom/android/internal/util/danda/OemPorts10TUtils;->onEngineGetCertificateChain()V\n' "$1"
}

instrumentationPatch() {
    local reg="$1" line="$2" retline=$(( $2 + 1 ))
    printf '    invoke-static {%s}, Lcom/android/internal/util/danda/OemPorts10TUtils;->onNewApplication(Landroid/content/Context;)V\n\n    .line %s\n' "$reg" "$retline"
}

genCertificate() {
    local descReg="$1" argsReg="$2" retReg="$3"
    printf '    invoke-static {p0, v0, %s, %s}, Lcom/android/internal/util/danda/OemPorts10TUtils;->genCertificate(Ljava/lang/Object;Ljava/lang/Object;Landroid/system/keystore2/KeyDescriptor;Ljava/util/Collection;)Landroid/system/keystore2/KeyMetadata;\n\n    move-result-object %s\n\n    if-eqz %s, :cond_skip_spoofing\n\n    return-object %s\n\n    :cond_skip_spoofing\n' \
        "$descReg" "$argsReg" "$retReg" "$retReg" "$retReg"
}

onGetKeyEntry() {
    local descReg="$1"
    printf '    invoke-static {p0, v0, %s}, Lcom/android/internal/util/danda/OemPorts10TUtils;->onGetKeyEntry(Ljava/lang/Object;Ljava/lang/Object;Landroid/system/keystore2/KeyDescriptor;)Landroid/system/keystore2/KeyEntryResponse;\n\n    move-result-object %s\n\n    if-eqz %s, :cond_skip_spoofing\n\n    return-object %s\n\n    :cond_skip_spoofing\n' \
        "$descReg" "$descReg" "$descReg" "$descReg"
}

onDeleteKey() {
    printf '    invoke-static {%s}, Lcom/android/internal/util/danda/OemPorts10TUtils;->onDeleteKey(Landroid/system/keystore2/KeyDescriptor;)V\n' "$1"
}

# ============================================================
#  STEP 1 — pre-flight checks
# ============================================================
step "Pre-flight checks"
[[ -f $dirnow/framework.jar          ]] || die "framework.jar not found in $dirnow"
[[ -f $dirnow/tool/APKEditor.jar     ]] || die "missing tool/APKEditor.jar"
[[ -f $dirnow/PIF/classes.dex        ]] || die "missing PIF/classes.dex"
sub "framework.jar      ✓"
sub "tool/APKEditor.jar ✓"
sub "PIF/classes.dex    ✓"

for cmd in java zip unzip zipalign sed awk grep find head tail mktemp wc; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done
sub "toolchain          ✓"

# ============================================================
#  STEP 2 — unpack framework.jar
# ============================================================
step "Unpacking framework.jar"
rm -rf frmwrk frmwrk_out.apk frmwrk.jar
apkeditor d -i framework.jar -o frmwrk >/dev/null
mv framework.jar frmwrk.jar
sub "decompiled into ./frmwrk"
sub "original moved to ./frmwrk.jar (temporary)"

# ============================================================
#  STEP 3 — locate target smali files
# ============================================================
step "Locating target smali files"
keystorespiclassfile=$(find frmwrk/ -name 'AndroidKeyStoreSpi.smali' -printf '%P\n' | head -n1)
instrumentationsmali=$(find frmwrk/ -name 'Instrumentation.smali'      -printf '%P\n' | head -n1)
keystore2classfile=$(find frmwrk/  -name 'KeyStore2.smali'             -printf '%P\n' | head -n1)
keystorelvlclassfile=$(find frmwrk/ -name 'KeyStoreSecurityLevel.smali' -printf '%P\n' | head -n1)

[[ -n $keystorespiclassfile  ]] || die "AndroidKeyStoreSpi.smali not found"
[[ -n $instrumentationsmali  ]] || die "Instrumentation.smali not found"
[[ -n $keystore2classfile    ]] || die "KeyStore2.smali not found"
[[ -n $keystorelvlclassfile  ]] || die "KeyStoreSecurityLevel.smali not found"

sub "AndroidKeyStoreSpi.smali      → $keystorespiclassfile"
sub "Instrumentation.smali         → $instrumentationsmali"
sub "KeyStore2.smali               → $keystore2classfile"
sub "KeyStoreSecurityLevel.smali   → $keystorelvlclassfile"

# ============================================================
#  STEP 4 — resolve method signatures
# ============================================================
step "Resolving method signatures"

engineGetCertMethod=$(expressions_fix "$(grep 'engineGetCertificateChain(' "frmwrk/$keystorespiclassfile" | head -n1)")
newAppMethod1=$(expressions_fix "$(grep ' newApplication(Ljava/lang/ClassLoader;' "frmwrk/$instrumentationsmali" | head -n1)")
newAppMethod2=$(expressions_fix "$(grep ' newApplication(Ljava/lang/Class;'        "frmwrk/$instrumentationsmali" | head -n1)")
getKeyEntryMethod=$(expressions_fix "$(grep ' getKeyEntry(Landroid/system/keystore2/KeyDescriptor;' "frmwrk/$keystore2classfile" | head -n1)")
deleteKeyMethod=$(expressions_fix "$(grep ' deleteKey(Landroid/system/keystore2/KeyDescriptor;'     "frmwrk/$keystore2classfile" | head -n1)")
genKeyMethod=$(expressions_fix "$(grep ' generateKey(Landroid/system/keystore2/KeyDescriptor;' "frmwrk/$keystorelvlclassfile" | head -n1)")

declare -A _labels=(
    [engineGetCertMethod]="AndroidKeyStoreSpi#engineGetCertificateChain"
    [newAppMethod1]="Instrumentation#newApplication(ClassLoader)"
    [newAppMethod2]="Instrumentation#newApplication(Class)"
    [getKeyEntryMethod]="KeyStore2#getKeyEntry"
    [deleteKeyMethod]="KeyStore2#deleteKey"
    [genKeyMethod]="KeyStoreSecurityLevel#generateKey"
)
for v in engineGetCertMethod newAppMethod1 newAppMethod2 getKeyEntryMethod deleteKeyMethod genKeyMethod; do
    [[ -n ${!v} ]] || die "failed to locate method: ${_labels[$v]}"
    sub "${_labels[$v]}  ✓"
done

# ============================================================
#  STEP 5 — extract method bodies
# ============================================================
step "Extracting method bodies"

sed -n "/^${engineGetCertMethod}/,/^\.end method/p" "frmwrk/$keystorespiclassfile" > tmp_keystore
sed -i "/^${engineGetCertMethod}/,/^\.end method/d" "frmwrk/$keystorespiclassfile"
sub "engineGetCertificateChain → tmp_keystore"

sed -n "/^${newAppMethod1}/,/^\.end method/p" "frmwrk/$instrumentationsmali" > inst1
sed -i "/^${newAppMethod1}/,/^\.end method/d" "frmwrk/$instrumentationsmali"
sub "newApplication(ClassLoader)  → inst1"

sed -n "/^${newAppMethod2}/,/^\.end method/p" "frmwrk/$instrumentationsmali" > inst2
sed -i "/^${newAppMethod2}/,/^\.end method/d" "frmwrk/$instrumentationsmali"
sub "newApplication(Class)        → inst2"

sed -n "/^${getKeyEntryMethod}/,/^\.end method/p" "frmwrk/$keystore2classfile" > getKeyEntry_tmp
sed -i "/^${getKeyEntryMethod}/,/^\.end method/d" "frmwrk/$keystore2classfile"
sub "getKeyEntry                  → getKeyEntry_tmp"

sed -n "/^${deleteKeyMethod}/,/^\.end method/p" "frmwrk/$keystore2classfile" > delKey_tmp
sed -i "/^${deleteKeyMethod}/,/^\.end method/d" "frmwrk/$keystore2classfile"
sub "deleteKey                    → delKey_tmp"

sed -n "/^${genKeyMethod}/,/^\.end method/p" "frmwrk/$keystorelvlclassfile" > genKey_tmp
sed -i "/^${genKeyMethod}/,/^\.end method/d" "frmwrk/$keystorelvlclassfile"
sub "generateKey                  → genKey_tmp"

# ============================================================
#  STEP 6 — instrument patches
# ============================================================
step "Applying instrumentation hooks"

inst1_insert=$(( $(wc -l < inst1) - 2 ))
instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst1 | head -n1 | awk '{print $3}' | sed 's/},//')
instline=$(( $(grep -r ".line" inst1 | tail -n1 | awk '{print $2}') + 1 ))
[[ -n $instreg ]] || die "inst1: Context register not found"
insert_after_line inst1 "$inst1_insert" "$(instrumentationPatch "$instreg" "$instline")"
sub "inst1: hooked onNewApplication (reg=$instreg, line=$instline)"

inst2_insert=$(( $(wc -l < inst2) - 2 ))
instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst2 | head -n1 | awk '{print $3}' | sed 's/},//')
instline=$(( $(grep -r ".line" inst2 | tail -n1 | awk '{print $2}') + 1 ))
[[ -n $instreg ]] || die "inst2: Context register not found"
insert_after_line inst2 "$inst2_insert" "$(instrumentationPatch "$instreg" "$instline")"
sub "inst2: hooked onNewApplication (reg=$instreg, line=$instline)"

kstoreline=$(( $(grep -r ".line" tmp_keystore | head -n1 | awk '{print $2}') - 2 ))
insert_after_line tmp_keystore 4 "$(certificatechainPatch "$kstoreline")"
sub "keystore: hooked onEngineGetCertificateChain (line=$kstoreline)"

# ============================================================
#  STEP 7 — keystore2 / security level hooks
# ============================================================
step "Applying keystore hooks"

# --- deleteKey ---
descReg=$(grep -E ', "descriptor" ' delKey_tmp | head -n1 | awk '{print $2}' | awk -F ',' '{print $1}')
[[ -n $descReg ]] || die "deleteKey: descriptor register not found"
del_payload=$(onDeleteKey "$descReg")
awk -v payload="$del_payload" '
    /new-instance .*, Landroid\/security\/KeyStore2\$\$ExternalSyntheticLambda/ {
        print payload
        print ""
    }
    { print $0 }
' delKey_tmp >> "frmwrk/$keystore2classfile"
sub "deleteKey hook applied (descReg=$descReg)"

# --- getKeyEntry ---
descReg=$(grep -E ', "descriptor" ' getKeyEntry_tmp | head -n1 | awk '{print $2}' | awk -F ',' '{print $1}')
[[ -n $descReg ]] || die "getKeyEntry: descriptor register not found"
getkey_payload=$(onGetKeyEntry "$descReg")
awk -v payload="$getkey_payload" '
    /invoke-virtual .*, Landroid\/security\/KeyStore2;->handleRemoteExceptionWithRetry/ {
        print payload
        print ""
    }
    { print $0 }
' getKeyEntry_tmp >> "frmwrk/$keystore2classfile"
sub "getKeyEntry hook applied (descReg=$descReg)"

# --- generateKey ---
descReg=$(grep -E '.local' genKey_tmp | grep -E ', "descriptor"' | head -n1 | awk '{print $2}' | awk -F ',' '{print $1}')
argsReg=$(grep -E '.local' genKey_tmp | grep -E ', "args"'       | tail -n1 | awk '{print $2}' | awk -F ',' '{print $1}')
retReg=$(grep -E 'return-object '   genKey_tmp | head -n1 | awk '{print $2}')
[[ -n $descReg && -n $argsReg && -n $retReg ]] || die "generateKey: register extraction failed"
gencert_payload=$(genCertificate "$descReg" "$argsReg" "$retReg")
awk -v payload="$gencert_payload" '
    /invoke-direct .*, Landroid\/security\/KeyStoreSecurityLevel;->handleExceptions/ {
        print payload
        print ""
    }
    { print $0 }
' genKey_tmp >> "frmwrk/$keystorelvlclassfile"
sub "generateKey hook applied (descReg=$descReg, argsReg=$argsReg, retReg=$retReg)"

# ============================================================
#  STEP 8 — restore patched method bodies
# ============================================================
step "Restoring patched method bodies"

cat inst1        >> "frmwrk/$instrumentationsmali"
cat inst2        >> "frmwrk/$instrumentationsmali"
cat tmp_keystore >> "frmwrk/$keystorespiclassfile"
sub "Instrumentation.smali         ← inst1 + inst2"
sub "AndroidKeyStoreSpi.smali      ← tmp_keystore"
sub "KeyStore2.smali               ← (appended inline)"
sub "KeyStoreSecurityLevel.smali   ← (appended inline)"

rm -f inst1 inst2 tmp_keystore getKeyEntry_tmp genKey_tmp delKey_tmp
sub "temporary files cleaned"

# ============================================================
#  STEP 9 — repack framework.jar
# ============================================================
step "Repacking framework.jar"

apkeditor b -i frmwrk >/dev/null
sub "rebuilt dex from smali"

unzip -o frmwrk_out.apk 'classes*.dex' -d frmwrk >/dev/null
sub "extracted classes*.dex"

rm -rf frmwrk/.cache
patchclass=$(( $(find frmwrk/ -type f -name '*.dex' | wc -l) + 1 ))
cp PIF/classes.dex "frmwrk/classes${patchclass}.dex"
sub "injected PIF/classes.dex → classes${patchclass}.dex"

(
    cd frmwrk
    zip -qr0 "$dirnow/frmwrk.jar" classes*.dex
)
sub "zipped dex into frmwrk.jar"

zipalign -f -v 4 frmwrk.jar framework.jar >/dev/null
sub "zipaligned → framework.jar"

# ============================================================
#  STEP 10 — cleanup + summary
# ============================================================
step "Cleanup"

rm -rf frmwrk.jar frmwrk frmwrk_out.apk
sub "intermediate files removed"

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
mm=$(( elapsed / 60 ))
ss=$(( elapsed % 60 ))

out_size=$(du -h "$dirnow/framework.jar" | awk '{print $1}')

printf '\n%s%s╔══════════════════════════════════════════════════════════╗%s\n' "$C_BOLD$C_GREEN" "" "$C_RESET"
printf '%s%s║              BUILD SUCCESSFUL                     ║%s\n' "$C_BOLD$C_GREEN" "" "$C_RESET"
printf '%s%s╚══════════════════════════════════════════════════════════╝%s\n' "$C_BOLD$C_GREEN" "" "$C_RESET"
printf '  %soutput   :%s %s\n'        "$C_GRAY" "$C_RESET" "$dirnow/framework.jar"
printf '  %ssize     :%s %s\n'        "$C_GRAY" "$C_RESET" "$out_size"
printf '  %sduration :%s %dm %02ds\n' "$C_GRAY" "$C_RESET" "$mm" "$ss"
printf '  %ssteps    :%s %d/%d\n'     "$C_GRAY" "$C_RESET" "$STEP" "$STEP_TOTAL"
printf '  %sfinished :%s %s\n\n'      "$C_GRAY" "$C_RESET" "$(date '+%Y-%m-%d %H:%M:%S')"

ok "framework.jar patched"
