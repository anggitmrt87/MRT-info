#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROP_URL="${PROP_URL:-https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/refs/heads/bot/device_prop/komodo_beta.prop}"
KEYBOX_URL="${KEYBOX_URL:-}"
KEYBOX_XML="${KEYBOX_XML:-$SCRIPT_DIR/keybox.xml}"
OUTPUT_ARRAYS="${OUTPUT_ARRAYS:-$PROJECT_ROOT/PIF/res/values/arrays.xml}"
OUTPUT_INFO="${OUTPUT_INFO:-$PROJECT_ROOT/PIF/info.txt}"

TMP_PROP=$(mktemp)
TMP_DIR=$(mktemp -d)
trap 'rm -f "$TMP_PROP"; rm -rf "$TMP_DIR"' EXIT

echo "[*] Mengunduh prop dari: $PROP_URL"
curl -fsSL "$PROP_URL" -o "$TMP_PROP"

declare -A PROP
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    PROP["$key"]="$value"
done < "$TMP_PROP"

get_prop() { echo "${PROP[$1]:-${2:-}}"; }

MANUFACTURER=$(get_prop "MANUFACTURER" "Google")
MODEL=$(get_prop "MODEL")
FINGERPRINT=$(get_prop "FINGERPRINT")
SECURITY_PATCH=$(get_prop "SECURITY_PATCH")
FIRST_API_LEVEL=$(get_prop "FIRST_API_LEVEL" "34")
SPOOF_VENDING_SDK=$(get_prop "SPOOF_VENDING_SDK" "false")
VERSION=$(get_prop "VERSION" "$(date +%Y.%m.%d)")

IFS=':' read -r FP_PART1 FP_PART2 FP_PART3 <<< "$FINGERPRINT"
IFS='/' read -r FP_BRAND FP_PRODUCT FP_DEVICE <<< "$FP_PART1"
IFS='/' read -r FP_RELEASE FP_ID FP_INCREMENTAL <<< "$FP_PART2"
IFS='/' read -r FP_TYPE FP_TAGS <<< "$FP_PART3"

BRAND=$(get_prop "BRAND" "$FP_BRAND")
PRODUCT=$(get_prop "PRODUCT" "$FP_PRODUCT")
DEVICE=$(get_prop "DEVICE" "$FP_DEVICE")
RELEASE=$(get_prop "RELEASE" "$FP_RELEASE")
ID=$(get_prop "ID" "$FP_ID")
INCREMENTAL=$(get_prop "INCREMENTAL" "$FP_INCREMENTAL")
TYPE=$(get_prop "TYPE" "$FP_TYPE")
TAGS=$(get_prop "TAGS" "$FP_TAGS")

if [[ ! "$RELEASE" =~ ^[0-9]+$ ]] && [[ -n "$SECURITY_PATCH" ]]; then
    RELEASE=$(echo "$SECURITY_PATCH" | tr -d '-' | cut -c1-6)
fi

echo "[*] BRAND=$BRAND  PRODUCT=$PRODUCT  DEVICE=$DEVICE"
echo "[*] ID=$ID  INCREMENTAL=$INCREMENTAL  RELEASE=$RELEASE"

download_keybox() {
    local url="$1"
    local output="$2"

    detect_url_type() {
        case "$1" in
            *drive.google.com*|*docs.google.com*) echo "google_drive" ;;
            *mega.nz*|*mega.co.nz*)               echo "mega" ;;
            *mediafire.com*)                      echo "mediafire" ;;
            *dropbox.com*)                        echo "dropbox" ;;
            *github.com*|*raw.githubusercontent.com*) echo "direct" ;;
            *sourceforge.net*)                    echo "sourceforge" ;;
            *)                                    echo "direct" ;;
        esac
    }

    local URL_TYPE
    URL_TYPE=$(detect_url_type "$url")
    echo "[*] Keybox URL type: $URL_TYPE"

    case "$URL_TYPE" in
        "google_drive")
            local FILE_ID
            if [[ $url =~ /d/([^/]+) ]]; then
                FILE_ID="${BASH_REMATCH[1]}"
            elif [[ $url =~ id=([^&]+) ]]; then
                FILE_ID="${BASH_REMATCH[1]}"
            else
                FILE_ID=$(echo "$url" | grep -o '[^/]*$')
            fi
            echo "[*] Google Drive File ID: $FILE_ID"

            if command -v gdown &> /dev/null; then
                if gdown "https://drive.google.com/uc?id=$FILE_ID" -O "$output"; then
                    return 0
                fi
            fi

            local CONFIRM
            CONFIRM=$(wget --quiet --save-cookies /tmp/kb_cookies.txt \
                --keep-session-cookies --no-check-certificate \
                "https://docs.google.com/uc?export=download&id=$FILE_ID" -O- \
                | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1/p')
            if wget --load-cookies /tmp/kb_cookies.txt \
                "https://docs.google.com/uc?export=download&confirm=$CONFIRM&id=$FILE_ID" \
                -O "$output"; then
                return 0
            fi
            ;;

        "mega")
            if command -v megadl &> /dev/null; then
                if megadl "$url" --path "$output"; then
                    return 0
                fi
            fi
            ;;

        "mediafire")
            local DIRECT_URL
            DIRECT_URL=$(curl -s "$url" | grep -o 'https://download[^"]*' | head -1)
            if [ -n "$DIRECT_URL" ]; then
                echo "[*] MediaFire direct link: $DIRECT_URL"
                if wget "$DIRECT_URL" -O "$output"; then
                    return 0
                fi
            fi
            ;;

        "dropbox")
            if [[ $url == *"?dl=0"* ]]; then
                url="${url/?dl=0/?dl=1}"
            elif [[ $url != *"?dl=1"* ]]; then
                url="${url}?dl=1"
            fi
            echo "[*] Dropbox direct link: $url"
            ;;

        "sourceforge")
            local PROJECT FILE
            PROJECT=$(echo "$url" | grep -o 'projects/[^/]*' | cut -d'/' -f2)
            FILE=$(echo "$url" | grep -o 'files/[^/]*' | cut -d'/' -f2)
            if [ -n "$PROJECT" ] && [ -n "$FILE" ]; then
                url="https://downloads.sourceforge.net/project/$PROJECT/$FILE"
                echo "[*] SourceForge direct link: $url"
            fi
            ;;
    esac

    echo "[*] Fallback universal download..."
    if command -v aria2c &> /dev/null; then
        if aria2c --check-certificate=false --max-tries=3 --timeout=300 \
            --max-connection-per-server=4 "$url" -o "$output"; then
            return 0
        fi
    fi
    if wget --progress=dot:giga --timeout=300 --tries=3 "$url" -O "$output"; then
        return 0
    fi
    if curl -L --connect-timeout 300 --retry 3 --progress-bar "$url" -o "$output"; then
        return 0
    fi
    return 1
}

if [[ -n "$KEYBOX_URL" ]]; then
    echo "[*] Mengunduh keybox dari: $KEYBOX_URL"
    if ! download_keybox "$KEYBOX_URL" "$KEYBOX_XML"; then
        echo "[!] Gagal download keybox dari URL." >&2
        exit 1
    fi
    if [[ ! -s "$KEYBOX_XML" ]]; then
        echo "[!] File keybox hasil download kosong/tidak valid." >&2
        exit 1
    fi
    echo "[*] Keybox berhasil diunduh: $KEYBOX_XML ($(stat -c%s "$KEYBOX_XML") bytes)"
fi

if [[ ! -f "$KEYBOX_XML" ]]; then
    echo "[!] File $KEYBOX_XML tidak ditemukan." >&2
    echo "[!] Set KEYBOX_URL atau taruh keybox.xml di: $SCRIPT_DIR" >&2
    exit 1
fi

echo "[*] Parsing $KEYBOX_XML..."

python3 - "$KEYBOX_XML" "$TMP_DIR" <<'PYEOF'
import xml.etree.ElementTree as ET
import sys, os

keybox_path, outdir = sys.argv[1], sys.argv[2]
root = ET.parse(keybox_path).getroot()

keybox_items = []

for key_idx, key_elem in enumerate(root.iter('Key')):
    pk = key_elem.find('PrivateKey')
    if pk is not None and pk.text and 'PRIVATE KEY' in pk.text:
        keybox_items.append(('key', pk.text.strip()))

    chain = key_elem.find('CertificateChain')
    if chain is not None:
        for cert in chain.findall('Certificate'):
            if cert.text and 'CERTIFICATE' in cert.text:
                keybox_items.append(('cert', cert.text.strip()))

for i, (kind, content) in enumerate(keybox_items):
    with open(os.path.join(outdir, f'item_{i:03d}_{kind}.pem'), 'w') as f:
        f.write(content)

with open(os.path.join(outdir, 'item_count'), 'w') as f:
    f.write(str(len(keybox_items)))

with open(os.path.join(outdir, 'item_order.txt'), 'w') as f:
    for i, (kind, _) in enumerate(keybox_items):
        f.write(f"{i:03d}\t{kind}\n")
PYEOF

KEYBOX_ITEM_COUNT=$(cat "$TMP_DIR/item_count")
echo "[*] Total item keybox: $KEYBOX_ITEM_COUNT"

echo "[*] Menulis $OUTPUT_ARRAYS..."
mkdir -p "$(dirname "$OUTPUT_ARRAYS")"

{
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<resources>'

    echo '    <string-array name="device_props">'
    printf '        <item>%s</item>\n' \
        "$MANUFACTURER" "$MODEL" "$FINGERPRINT" "$BRAND" \
        "$PRODUCT" "$DEVICE" "$SECURITY_PATCH" "$FIRST_API_LEVEL"
    echo '    </string-array>'

    echo '    <string-array name="full_device_props">'
    printf '        <item>%s</item>\n' \
        "$MANUFACTURER" "$MODEL" "$FINGERPRINT" "$BRAND" \
        "$PRODUCT" "$DEVICE" "$RELEASE" "$ID" "$INCREMENTAL" \
        "$TYPE" "$TAGS" "$SECURITY_PATCH" "$FIRST_API_LEVEL"
    echo '    </string-array>'

    echo '    <string-array name="keybox">'
    while IFS=$'\t' read -r idx kind; do
        [[ -z "$idx" ]] && continue
        FILE=$(find "$TMP_DIR" -name "item_${idx}_*.pem" | head -n1)
        if [[ "$kind" == "key" ]]; then
            echo '        <item>"'
            cat "$FILE"
            echo ''
            echo '            "</item>'
        else
            echo '        <item>"'
            cat "$FILE"
            echo ''
            echo '                "</item>'
        fi
    done < "$TMP_DIR/item_order.txt"
    echo '    </string-array>'

    echo '    <string-array name="vendor_props">'
    echo '        <item>null</item>'
    echo '    </string-array>'

    echo '</resources>'
} > "$OUTPUT_ARRAYS"

echo "[*] Menulis $OUTPUT_INFO..."
mkdir -p "$(dirname "$OUTPUT_INFO")"

cat > "$OUTPUT_INFO" << EOF
VERSION           : ${VERSION}
--------------------------------
MANUFACTURER      : ${MANUFACTURER}
MODEL 	          : ${MODEL}
FINGERPRINT       : ${FINGERPRINT}
BRAND             : ${BRAND}
PRODUCT           : ${PRODUCT}
DEVICE            : ${DEVICE}
RELEASE           : ${RELEASE}
ID                : ${ID}
INCREMENTAL       : ${INCREMENTAL}
TYPE              : ${TYPE}
TAGS              : ${TAGS}
SECURITY PATCH    : ${SECURITY_PATCH}
FIRST API LEVEL   : ${FIRST_API_LEVEL}
SPOOF VENDING SDK : ${SPOOF_VENDING_SDK}
KEYBOX            : CUSTOM (${KEYBOX_ITEM_COUNT})
EOF

echo ""
echo "============================================"
echo " ✅ Selesai!"
echo "   - $OUTPUT_ARRAYS"
echo "   - $OUTPUT_INFO"
echo "   Keybox items: ${KEYBOX_ITEM_COUNT}"
echo "============================================"
