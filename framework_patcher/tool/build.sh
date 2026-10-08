#!/bin/bash

set -e

if [ "$1" == "--local-aapt" ];then
    export LD_LIBRARY_PATH=.
    export PATH=.:$PATH
    shift
fi

script_dir="$(dirname "$(readlink -f -- "$0")")"
if [ "$#" -eq 1 ]; then
    if [ -d "$1" ];then
	    makes="$(find "$1" -name Android.mk -exec readlink -f -- '{}' \;)"
    else
	    makes="$(readlink -f -- "$1")"
    fi
else
    cd "$script_dir"
    makes="$(find "$PWD/.." -name Android.mk)"
fi

if ! command -v aapt > /dev/null;then
    export LD_LIBRARY_PATH=.
    export PATH=$PATH:.
fi

if ! command -v aapt > /dev/null && ! command -v aapt2 > /dev/null; then
    echo "Please install aapt or aapt2 (apt install aapt or aapt2)"
    exit 1
fi

cd "$script_dir"

root_dir="$(cd "$script_dir/../.." && pwd)"
overlay_mk="$root_dir/overlay.mk"

declare -a product_packages
declare -a vendor_packages

if [ -f "$overlay_mk" ]; then
    current_section=""
    while IFS= read -r line; do
        line="${line%\\}"
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue

        if [[ "$line" == "# product overlay" ]]; then
            current_section="product"
            continue
        elif [[ "$line" == "# vendor overlay" ]]; then
            current_section="vendor"
            continue
        fi

        [[ "$line" == \#* ]] && continue

        if [[ "$current_section" == "product" ]]; then
            product_packages+=("$line")
        elif [[ "$current_section" == "vendor" ]]; then
            vendor_packages+=("$line")
        fi
    done < "$overlay_mk"
else
    echo "Warning: overlay.mk not found, APKs will stay in build/"
fi

contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

build_with_aapt() {
    local name="$1"
    local path="$2"
    
    local temp_android_data="$PWD/android_data_$$"
    mkdir -p "$temp_android_data"
    export ANDROID_DATA="$temp_android_data"
    
    aapt package -f --auto-add-overlay -F "${name}-unsigned.apk" -M "$path/AndroidManifest.xml" -S "$path/res" -I android.jar
    local ret=$?
    
    rm -rf "$temp_android_data"
    unset ANDROID_DATA
    return $ret
}

build_with_aapt2() {
    local name="$1"
    local path="$2"
    local temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN
    aapt2 compile -o "$temp_dir" --dir "$path/res" || return 1
    local flat_files=$(find "$temp_dir" -name "*.flat")
    if [ -z "$flat_files" ]; then
        echo "No resources compiled for $name"
        return 1
    fi
    aapt2 link --auto-add-overlay -o "${name}-unsigned.apk" -I android.jar --manifest "$path/AndroidManifest.xml" $flat_files || return 1
}

echo "$makes" | while read -r f; do
    # PERBAIKAN: Mengambil hanya 1 baris pertama dan mencocokkan dengan tepat
    name="$(sed -nE 's/^LOCAL_(PACKAGE_NAME|MODULE)[ \t]*:=[ \t]*([^ \t]+).*/\2/p' "$f" | head -n 1)"
    
    if [ -z "$name" ]; then
        echo "Error: Gagal menemukan nama module di $f. Melewati file ini."
        continue
    fi

    echo "Generating $name"
    path="$(dirname "$f")"
    
    if command -v aapt2 > /dev/null && build_with_aapt2 "$name" "$path"; then
        echo "Successfully built with aapt2"
    elif build_with_aapt "$name" "$path"; then
        echo "Successfully built with aapt"
    else
        echo "Failed to build $name with both aapt and aapt2"
        exit 1
    fi
    
    LD_LIBRARY_PATH=./signapk/ java -jar signapk/signapk.jar keys/platform.x509.pem keys/platform.pk8 "${name}-unsigned.apk" "${name}.apk"
    rm -f "${name}-unsigned.apk"

    if [ -f "$overlay_mk" ]; then
        if contains "$name" "${product_packages[@]}"; then
            target_dir="$root_dir/product/overlay"
        elif contains "$name" "${vendor_packages[@]}"; then
            target_dir="$root_dir/vendor/overlay"
        else
            target_dir="$root_dir/build"
        fi
        mkdir -p "$target_dir"
        mv "${name}.apk" "$target_dir/"
        echo "Moved ${name}.apk to $target_dir"
    fi
done
