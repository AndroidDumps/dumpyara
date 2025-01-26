#!/usr/bin/env bash

# Add logging definition to make output clearer
## Info
LOGI() {
    echo -e "[\033[32mINFO\033[0m]: ${1}"
}

## Warning
LOGW() {
    echo -e "[\033[33mWARNING\033[0m]: ${1}"
}

## Error
LOGE() {
    echo -e "[\033[31mERROR\033[0m] $(basename ${0}): ${1}"
}

## Fatal
LOGF() {
    echo -e "[\033[41mFATAL\033[0m] $(basename ${0}): ${1}"
    exit 1
}

[[ $# = 0 ]] && \
    LOGF "No input provided."

OS=$(uname)
if [ "$OS" = 'Darwin' ]; then
    export LC_CTYPE=C
fi

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Create input & working directory if it does not exist
mkdir -p "$PROJECT_DIR"/input "$PROJECT_DIR"/working

# Determine which command to use for privilege escalation
if command -v sudo > /dev/null 2>&1; then
    sudo_cmd="sudo"
elif command -v doas > /dev/null 2>&1; then
    sudo_cmd="doas"
else
    LOGW "Neither 'sudo' nor 'doas' found; resorting to 'su'."
    # Create a separated function in order to handle 'su'
    su_cmd() { 
        su -c "$*" 
    }
    sudo_cmd="su_cmd"
fi

# Activate virtual environment
source .venv/bin/activate

# GitHub token
if [[ -n $2 ]]; then
    GIT_OAUTH_TOKEN=$2
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(< .githubtoken)
else
    LOGW "GitHub token not found. Dumping just locally..."
fi

# download or copy from local?
if echo "$1" | grep -e '^\(https\?\|ftp\)://.*$' > /dev/null; then
    URL="$1"

    # Override '${URL}' with best possible mirror of it
    case "${URL}" in
        # For Xiaomi: replace '${URL}' with (one of) the fastest mirror
        *"d.miui.com"*)
            # Do not run this loop in case we're already using one of the reccomended mirrors
            if ! echo "${URL}" | rg -q 'cdnorg|bkt-sgp-miui-ota-update-alisgp'; then
                # Set '${URL_ORIGINAL}' and '${FILE_PATH}' in case we might need to roll back
                URL_ORIGINAL=$(echo "${URL}" | sed -E 's|(https://[^/]+).*|\1|')
                FILE_PATH=$(echo ${URL#*d.miui.com/} | sed 's/?.*//')

                # Array of different possible mirrors
                MIRRORS=(
                    "https://cdnorg.d.miui.com"
                    "https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com"
                    "https://bn.d.miui.com"
                    "${URL_ORIGINAL}"
                )

                # Check back and forth for the best available mirror
                for URLS in "${MIRRORS[@]}"; do
                    # Change mirror's domain with one(s) from array
                    URL=${URLS}/${FILE_PATH}

                    # Be sure that the mirror is available. Once found, break the loop 
                    if [ "$(curl -I -sS "${URL}" | head -n1 | cut -d' ' -f2)" == "404" ]; then
                        LOGW "${URLS} is not available. Trying with other mirror(s)..."
                    else
                        LOGI "Found best available mirror."
                        break
                    fi
                done
            fi
            ;;
            # For Pixeldrain: replace the link with a direct one
            *"pixeldrain.com/u"*)
                LOGI "Replacing with best available mirror."
                URL="https://pd.cybar.xyz/${URL##*/}"
            ;;
            *"pixeldrain.com/d"*)
                LOGI "Replacing with direct download link."
                URL="https://pixeldrain.com/api/filesystem/${URL##*/}"
            ;;
        esac
    
    # Download to the 'input/' directory
    cd "$PROJECT_DIR"/input || exit
    echo "${URL}"
    { type -p aria2c > /dev/null 2>&1 && printf "Downloading File...\n" && aria2c -x16 -j"$(nproc)" "${URL}"; } || { printf "Downloading File...\n" && wget -q --content-disposition --show-progress --progress=bar:force "${URL}" || exit 1; }
    if [[ ! -f "$(echo "${URL##*/}" | inline-detox)" ]]; then
        URL=$(wget --server-response --spider "${URL}" 2>&1 | awk -F"filename=" '{print $2}')
    fi
    detox "${URL##*/}"
else
    URL=$(printf "%s\n" "$1")
    [[ -e "$URL" ]] || { echo "Invalid Input" && exit 1; }
fi

ORG=AndroidDumps #your GitHub org name
FILE=$(echo "${URL##*/}" | inline-detox)
EXTENSION=$(echo "${URL##*.}" | inline-detox)
UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system systemex system_ext system_other vendor cust odm odm_ext oem factory product modem xrom oppo_product opproduct reserve india my_preload my_odm my_stock my_operator my_country my_product my_company my_engineering my_heytap my_custom my_manifest my_carrier my_region my_bigball my_version special_preload vendor_dlkm odm_dlkm system_dlkm mi_ext"

if [[ -d "$1" ]]; then
    LOGI 'Directory detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/working/"${UNZIP_DIR}"
elif [[ -f "$1" ]]; then
    LOGI 'File detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/input/"${FILE}" > /dev/null 2>&1
fi

# clone other repo's
if [[ -d "$PROJECT_DIR/Firmware_extractor" ]]; then
    git -C "$PROJECT_DIR"/Firmware_extractor pull --recurse-submodules --rebase
else
    git clone -q --recurse-submodules https://github.com/AndroidDumps/Firmware_extractor "$PROJECT_DIR"/Firmware_extractor
fi

# extract rom via Firmware_extractor
[[ ! -d "$1" ]] && bash "$PROJECT_DIR"/Firmware_extractor/extractor.sh "$PROJECT_DIR"/input/"${FILE}" "$PROJECT_DIR"/working/"${UNZIP_DIR}"

# Retrive 'extract-ikconfig' from torvalds/linux
if ! [[ -f "${PROJECT_DIR}"/extract-ikconfig ]]; then
    curl -s -Lo "${PROJECT_DIR}"/extract-ikconfig https://raw.githubusercontent.com/torvalds/linux/refs/heads/master/scripts/extract-ikconfig
    chmod +x "${PROJECT_DIR}"/extract-ikconfig
fi

# Set path for tools
UNPACKBOOTIMG="${PROJECT_DIR}"/Firmware_extractor/tools/unpackbootimg
VMLINUX_TO_ELF="uvx -q --from git+https://github.com/marin-m/vmlinux-to-elf@da14e789596d493f305688e221e9e34ebf63cbb8"
EXTRACT_IKCONFIG="${PROJECT_DIR}"/extract-ikconfig

# extract PARTITIONS
cd "$PROJECT_DIR"/working/"${UNZIP_DIR}" || exit
for p in $PARTITIONS; do
    # Try to extract images via fsck.erofs
    if [ -f "$p".img ] && [ "$p" != "modem" ]; then
        LOGI "Trying to extract $p partition via fsck.erofs."
        "$PROJECT_DIR"/Firmware_extractor/tools/fsck.erofs --extract="$p" "$p".img
        # Deletes images if they were correctly extracted via fsck.erofs
        if [ -d "$p" ]; then
            rm "$p".img > /dev/null 2>&1
        else
        # Uses 7z if images could not be extracted via fsck.erofs
            if [[ -e "$p.img" ]]; then
                mkdir "$p" 2> /dev/null || rm -rf "${p:?}"/*
                LOGW "Extraction via fsck.erofs failed, extracting $p partition via 7z"
                if 7z x "$p".img -y -o"$p"/ > /dev/null 2>&1; then
                    rm "$p".img > /dev/null 2>&1
                else
                    LOGW "Couldn't extract $p partition via 7z. Using mount loop"
                    $sudo_cmd mount -o loop -t auto "$p".img "$p"
                    mkdir "${p}_"
                    $sudo_cmd cp -rf "${p}/"* "${p}_"
                    $sudo_cmd umount "${p}"
                    $sudo_cmd cp -rf "${p}_/"* "${p}"
                    if $sudo_cmd rm -rf "${p}_"; then
                        rm -fv "$p".img > /dev/null 2>&1
                    else
                        LOGE "Couldn't extract $p partition. It might use an unsupported filesystem."
                        echo "        For EROFS: make sure you're using Linux 5.4+ kernel."
                        echo "        For F2FS: make sure you're using Linux 5.15+ kernel."
                    fi
                fi
            fi
        fi
    fi
done

# Extract and decompile device-tree blobs
for image in boot vendor_boot vendor_kernel_boot; do
    if [[ -f "${image}".img ]]; then
        # Create working directories
        mkdir -p "${image}/dtb" "${image}/dts"

        # Unpack image's content
        LOGI "Extracting '${image}' content..."
        ${UNPACKBOOTIMG} -i "${image}.img" -o "${image}/" > /dev/null || \
            LOGE "Extraction via 'unpackbootimg' unsuccessful."

        ## Retrive image's ramdisk, and extract it
        unlz4 "${image}"/"${image}".img-*ramdisk "${image}/ramdisk.lz4" >> /dev/null 2>&1
        7z -snld x "${image}/ramdisk.lz4" -o"${image}/ramdisk" >> /dev/null 2>&1  || \
            LOGI "Failed to extract ramdisk."

        ## Clean-up
        rm -rf "${image}/ramdisk.lz4"
        rm -rf "${image}/${image}".img-*ramdisk

        # Extract 'dtb' via 'extract-dtb'
        LOGI "Trying to extract device-tree(s) from '${image}'..." 
        uvx -q extract-dtb "${image}.img" -o "${image}/dtb" > /dev/null || \
            LOGE "Failed to extract device-tree blobs."

        # Remove '00_kernel'
        rm -rf "${image}/dtb/00_kernel"

        # Decompile blobs to 'dts' via 'dtc'
        for dtb in $(find "${image}/dtb" -type f); do
            dtc -q -I dtb -O dts "${dtb}" >> "${image}/dts/$(basename "${dtb}" | sed 's/\.dtb/.dts/')" || \
                LOGE "Failed to decompile device-tree blobs."
        done
    fi

    # If no device-tree were extracted or decompiled, delete the directories
    if [ ! "$(ls -A ${image}/dtb)" ]; then
        rm -rf "${image}/dtb" "${image}/dts"
    fi
done

# Extract 'boot.img'-related content
if [[ -f boot.img ]]; then
    # Extract 'ikconfig'
    LOGI "Extracting 'ikconfig'..."
    ${EXTRACT_IKCONFIG} boot.img > ikconfig || {
        LOGE "Failed to generate 'ikconfig'"
    }

    # Generate non-stack symbols
    LOGI "Generating 'boot.img-kallsyms'..."
    ${VMLINUX_TO_ELF} kallsyms-finder boot.img > boot/boot.img-kallsyms || \
        LOGE "Failed to generate 'boot.img-kallsyms'"

    # Generate analyzable '.elf'
    LOGI "Extracting 'boot.img-elf'..."
    ${VMLINUX_TO_ELF} vmlinux-to-elf boot.img boot/boot.img-elf > /dev/null ||
        LOGE "Failed to generate 'boot.img-elf'"
fi

# Extract 'dtbo.img' separately
if [[ -f dtbo.img ]]; then
    # Create working directories
    mkdir -p "dtbo/dts"

    # Extract 'dtb' via 'extract-dtb'
    LOGI "Trying to extract device-tree(s) from 'dtbo'..." 
    uvx -q extract-dtb "dtbo.img" -o "dtbo/" > /dev/null || \
        LOGE "Failed to extract device-tree blobs."

    # Remove '00_kernel'
    rm -rf "dtbo/00_kernel"

    # Decompile blobs to 'dts' via 'dtc'
    for dtb in $(find "dtbo" -type f -name "*.dtb"); do
        dtc -q -I dtb -O dts "${dtb}" >> "dtbo/dts/$(basename "${dtb}" | sed 's/\.dtb/.dts/')" || \
            LOGE "Failed to decompile device-tree blobs."
    done
fi

# Fix permissions
$sudo_cmd chown "$(whoami)" "$PROJECT_DIR"/working/"${UNZIP_DIR}"/./* -fR
$sudo_cmd chmod -fR u+rwX "$PROJECT_DIR"/working/"${UNZIP_DIR}"/./*

# board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/modem -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/tz* -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
if [ -e "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop ]; then
    strings "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
fi
sort -u -o "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt

# 'flavor' property (e.g. caiman-user)
flavor=$(rg -m1 -INoP --no-messages "(?<=^ro.build.flavor=).*" {vendor,system,system/system}/build.prop)
[[ -z ${flavor} ]] && flavor=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.flavor=).*" vendor/build*.prop)
[[ -z ${flavor} ]] && flavor=$(rg -m1 -INoP --no-messages "(?<=^ro.build.flavor=).*" {vendor,system,system/system}/build*.prop)
[[ -z ${flavor} ]] && flavor=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.flavor=).*" {system,system/system}/build*.prop)
[[ -z ${flavor} ]] && flavor=$(rg -m1 -INoP --no-messages "(?<=^ro.build.type=).*" {system,system/system}/build*.prop)

# 'release' property (e.g. 15)
release=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.release=).*" {my_manifest,vendor,system,system/system}/build*.prop)
[[ -z ${release} ]] && release=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.version.release=).*" vendor/build*.prop)
[[ -z ${release} ]] && release=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.version.release=).*" {system,system/system}/build*.prop)
release=$(echo "$release" | head -1)

# 'id' property (e.g. AP4A.241205.013)
id=$(rg -m1 -INoP --no-messages "(?<=^ro.build.id=).*" my_manifest/build*.prop)
[[ -z ${id} ]] && id=$(rg -m1 -INoP --no-messages "(?<=^ro.build.id=).*" system/system/build_default.prop)
[[ -z ${id} ]] && id=$(rg -m1 -INoP --no-messages "(?<=^ro.build.id=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${id} ]] && id=$(rg -m1 -INoP --no-messages "(?<=^ro.build.id=).*" {vendor,system,system/system}/build*.prop)
[[ -z ${id} ]] && id=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.id=).*" vendor/build*.prop)
[[ -z ${id} ]] && id=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.id=).*" {system,system/system}/build*.prop)
id=$(echo "$id" | head -1)

# 'incremental' property (e.g. 12621605)
incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.incremental=).*" my_manifest/build*.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.incremental=).*" system/system/build_default.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.incremental=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.incremental=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.version.incremental=).*" my_manifest/build*.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.version.incremental=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.version.incremental=).*" vendor/build*.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.version.incremental=).*" {system,system/system}/build*.prop | head -1)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.build.version.incremental=).*" my_product/build*.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.version.incremental=).*" my_product/build*.prop)
[[ -z ${incremental} ]] && incremental=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.version.incremental=).*" my_product/build*.prop)
incremental=$(echo "$incremental" | head -1)

# 'tags' property (e.g. release-keys)
tags=$(rg -m1 -INoP --no-messages "(?<=^ro.build.tags=).*" {vendor,system,system/system}/build*.prop)
[[ -z ${tags} ]] && tags=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.tags=).*" vendor/build*.prop)
[[ -z ${tags} ]] && tags=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.tags=).*" {system,system/system}/build*.prop)
tags=$(echo "$tags" | head -1)

# 'platform' property (e.g. zumapro)
platform=$(rg -m1 -INoP --no-messages "(?<=^ro.board.platform=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${platform} ]] && platform=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.board.platform=).*" vendor/build*.prop)
[[ -z ${platform} ]] && platform=$(rg -m1 -INoP --no-messages rg"(?<=^ro.system.board.platform=).*" {system,system/system}/build*.prop)
platform=$(echo "$platform" | head -1)

# 'manufacturer' property (e.g. google)
manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.manufacturer=).*" odm/etc/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" odm/etc/fingerprint/build.default.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" my_product/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" my_manifest/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" system/system/build_default.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand.sub=).*" my_product/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand.sub=).*" system/system/euclid/my_product/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.manufacturer=).*" vendor/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.manufacturer=).*" my_manifest/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.manufacturer=).*" system/system/build_default.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.manufacturer=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.manufacturer=).*" vendor/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.system.product.manufacturer=).*" {system,system/system}/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.manufacturer=).*" {system,system/system}/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.manufacturer=).*" my_manifest/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.manufacturer=).*" system/system/build_default.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.manufacturer=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.manufacturer=).*" vendor/odm/etc/build*.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" {oppo_product,my_product}/build*.prop | head -1)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.manufacturer=).*" vendor/euclid/*/build.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.system.product.manufacturer=).*" vendor/euclid/*/build.prop)
[[ -z ${manufacturer} ]] && manufacturer=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.manufacturer=).*" vendor/euclid/product/build*.prop)
manufacturer=$(echo "$manufacturer" | head -1)

# 'fingerprint' property (e.g. google/caiman/caiman:15/AP4A.241205.013/12621605:user/release-keys)
fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.odm.build.fingerprint=).*" odm/etc/*build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" my_manifest/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" system/system/build_default.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" odm/etc/fingerprint/build.default.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" vendor/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fingerprint=).*" my_manifest/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fingerprint=).*" system/system/build_default.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fingerprint=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fingerprint=).*"  {system,system/system}/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.product.build.fingerprint=).*" product/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.fingerprint=).*" {system,system/system}/build*.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fingerprint=).*" my_product/build.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.fingerprint=).*" my_product/build.prop)
[[ -z ${fingerprint} ]] && fingerprint=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.fingerprint=).*" my_product/build.prop)
fingerprint=$(echo "$fingerprint" | head -1)

# 'codename' property (e.g. caiman)
codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.device=).*" odm/etc/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.device=).*" system/system/build_default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" odm/etc/fingerprint/build.default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" my_manifest/build*.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" system/system/build_default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.device=).*" system/system/build_default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.device=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.device=).*" system/system/build_default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.device=).*" vendor/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.device=).*" vendor/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.device.oem=).*" odm/build.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.device.oem=).*" vendor/euclid/odm/build.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.device=).*" my_manifest/build*.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.device=).*" {system,system/system}/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.device=).*" vendor/euclid/*/build.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.device=).*" vendor/euclid/*/build.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.device=).*" system/system/build_default.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.model=).*" vendor/euclid/*/build.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.device=).*" {oppo_product,my_product}/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.device=).*" oppo_product/build*.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.device=).*" my_product/build*.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.device=).*" my_product/build*.prop)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.build.fota.version=).*" {system,system/system}/build*.prop | cut -d - -f1 | head -1)
[[ -z ${codename} ]] && codename=$(rg -m1 -INoP --no-messages "(?<=^ro.build.product=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${codename} ]] && codename=$(echo "$fingerprint" | cut -d / -f3 | cut -d : -f1)

# 'brand' property (e.g. google)
brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" odm/etc/"${codename}"_build.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" odm/etc/build*.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" system/system/build_default.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" odm/etc/fingerprint/build.default.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" my_product/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" system/system/build_default.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" {vendor,system,system/system}/build*.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand.sub=).*" my_product/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand.sub=).*" system/system/euclid/my_product/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.brand=).*" my_manifest/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.brand=).*" system/system/build_default.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.brand=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.vendor.brand=).*" vendor/build*.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.product.brand=).*" vendor/build*.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.brand=).*" {system,system/system}/build*.prop | head -1)
[[ -z ${brand} || ${brand} == "OPPO" ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.system.brand=).*" vendor/euclid/*/build.prop | head -1)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.product.brand=).*" vendor/euclid/product/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" my_manifest/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" vendor/euclid/my_manifest/build.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.odm.brand=).*" vendor/odm/etc/build*.prop)
[[ -z ${brand} ]] && brand=$(rg -m1 -INoP --no-messages "(?<=^ro.product.brand=).*" {oppo_product,my_product}/build*.prop | head -1)
[[ -z ${brand} ]] && brand=$(echo "$fingerprint" | cut -d / -f1)
[[ -z ${brand} ]] && brand="$manufacturer"

# 'description' property (e.g. caiman-user 15 AP4A.241205.013 12621605 release-keys)
description=$(rg -m1 -INoP --no-messages "(?<=^ro.build.description=).*" {system,system/system}/build.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.build.description=).*" {system,system/system}/build*.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.description=).*" vendor/build.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.vendor.build.description=).*" vendor/build*.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.product.build.description=).*" product/build.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.product.build.description=).*" product/build*.prop)
[[ -z ${description} ]] && description=$(rg -m1 -INoP --no-messages "(?<=^ro.system.build.description=).*" {system,system/system}/build*.prop)
[[ -z ${description} ]] && description="$flavor $release $id $incremental $tags"

is_ab=$(grep -oP "(?<=^ro.build.ab_update=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${is_ab}" ]] && is_ab="false"
branch=$(echo "$description" | tr ' ' '-')
repo=$(echo "$brand"_"$codename"_dump | tr '[:upper:]' '[:lower:]' | tr -d '\r\n')
platform=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
top_codename=$(echo "$codename" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
manufacturer=$(echo "$manufacturer" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
printf "# %s\n- manufacturer: %s\n- platform: %s\n- codename: %s\n- flavor: %s\n- release: %s\n- id: %s\n- incremental: %s\n- tags: %s\n- fingerprint: %s\n- is_ab: %s\n- brand: %s\n- branch: %s\n- repo: %s\n" "$description" "$manufacturer" "$platform" "$codename" "$flavor" "$release" "$id" "$incremental" "$tags" "$fingerprint" "$is_ab" "$brand" "$branch" "$repo" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md
cat "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md

# Generate AOSP device tree
mkdir -p "${PROJECT_DIR}/working/${UNZIP_DIR}/aosp-device-tree"
if uvx aospdtgen . --output "${PROJECT_DIR}/working/${UNZIP_DIR}/aosp-device-tree"; then
    LOGI "AOSP device tree successfully generated"
else
    LOGE "Failed to generate AOSP device tree"
fi

# copy file names
chown "$(whoami)" ./* -R
chmod -R u+rwX ./* #ensure final permissions
find "$PROJECT_DIR"/working/"${UNZIP_DIR}" -type f -printf '%P\n' | sort | grep -v ".git/" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/all_files.txt

if [[ -n $GIT_OAUTH_TOKEN ]]; then
    GITPUSH=(git push https://"$GIT_OAUTH_TOKEN"@github.com/"$ORG"/"${repo,,}".git "$branch")
    curl --silent --fail "https://raw.githubusercontent.com/$ORG/$repo/$branch/all_files.txt" 2> /dev/null && echo "Firmware already dumped!" && exit 1
    git init
    if [[ -z "$(git config --get user.email)" ]]; then
        git config user.email AndroidDumps@github.com
    fi
    if [[ -z "$(git config --get user.name)" ]]; then
        git config user.name AndroidDumps
    fi
    curl -s -X POST -H "Authorization: token ${GIT_OAUTH_TOKEN}" -d '{ "name": "'"$repo"'" }' "https://api.github.com/orgs/${ORG}/repos" #create new repo
    curl -s -X PUT -H "Authorization: token ${GIT_OAUTH_TOKEN}" -H "Accept: application/vnd.github.mercy-preview+json" -d '{ "names": ["'"$manufacturer"'","'"$platform"'","'"$top_codename"'"]}' "https://api.github.com/repos/${ORG}/${repo}/topics"
    git remote add origin https://github.com/$ORG/"${repo,,}".git
    git checkout -b "$branch"
    find . -size +97M -printf '%P\n' -o -name "*sensetime*" -printf '%P\n' -o -name "*.lic" -printf '%P\n' >| .gitignore
    git add --all
    git commit -asm "Add ${description}"
    git update-ref -d HEAD
    git reset system/ vendor/ product/
    git checkout -b "$branch"
    git commit -asm "Add extras for ${description}" && "${GITPUSH[@]}"
    git add vendor/
    git commit -asm "Add vendor for ${description}" && "${GITPUSH[@]}"
    git add system/system/app/ || git add system/app/
    git commit -asm "Add system app for ${description}" && "${GITPUSH[@]}"
    git add system/system/priv-app/ || git add system/priv-app/
    git commit -asm "Add system priv-app for ${description}" && "${GITPUSH[@]}"
    git add system/
    git commit -asm "Add system for ${description}" && "${GITPUSH[@]}"
    git add product/app/
    git commit -asm "Add product app for ${description}" && "${GITPUSH[@]}"
    git add product/priv-app/
    git commit -asm "Add product priv-app for ${description}" && "${GITPUSH[@]}"
    git add product/
    git commit -asm "Add product for ${description}" && "${GITPUSH[@]}"
else
    LOGI "Dump done locally."
    exit 1
fi

# Telegram channel
TG_TOKEN=$(< "$PROJECT_DIR"/.tgtoken)
if [[ -n "$TG_TOKEN" ]]; then
    CHAT_ID="@android_dumps"
    commit_head=$(git log --format=format:%H | head -n 1)
    commit_link="https://github.com/$ORG/$repo/commit/$commit_head"
    echo -e "Sending telegram notification"
    printf "<b>Brand: %s</b>" "$brand" >| "$PROJECT_DIR"/working/tg.html
    {
        printf "\n<b>Device: %s</b>" "$codename"
        printf "\n<b>Version:</b> %s" "$release"
        printf "\n<b>Fingerprint:</b> %s" "$fingerprint"
        printf "\n<b>GitHub:</b>"
        printf "\n<a href=\"%s\">Commit</a>" "$commit_link"
        printf "\n<a href=\"https://github.com/%s/%s/tree/%s/\">%s</a>" "$ORG" "$repo" "$branch" "$codename"
    } >> "$PROJECT_DIR"/working/tg.html
    TEXT=$(< "$PROJECT_DIR"/working/tg.html)
    curl -s "https://api.telegram.org/bot${TG_TOKEN}/sendmessage" --data "text=${TEXT}&chat_id=${CHAT_ID}&parse_mode=HTML&disable_web_page_preview=True" > /dev/null
    rm -rf "$PROJECT_DIR"/working/tg.html
fi
