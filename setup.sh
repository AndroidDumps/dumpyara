#!/bin/bash

# Determine which command to use for privilege escalation
if command -v sudo > /dev/null 2>&1; then
    sudo_cmd="sudo"
elif command -v doas > /dev/null 2>&1; then
    sudo_cmd="doas"
else
    echo "Neither sudo nor doas found. Please install one of them."
    exit 1
fi

if [[ "$OSTYPE" == "linux-gnu" ]]; then
    if [[ "$(command -v apt)" != "" ]]; then
        $sudo_cmd apt install unace unrar zip unzip p7zip-full p7zip-rar sharutils rar uudeview mpack arj cabextract device-tree-compiler liblzma-dev python3-pip brotli liblz4-tool axel gawk aria2 detox cpio rename liblz4-dev curl python3-venv -y
    elif [[ "$(command -v dnf)" != "" ]]; then
        $sudo_cmd dnf install -y unace unrar zip unzip sharutils uudeview arj cabextract file-roller dtc python3-pip brotli axel aria2 detox cpio lz4 python3-devel xz-devel p7zip p7zip-plugins
    elif [[ "$(command -v pacman)" != "" ]]; then
        $sudo_cmd pacman -Sy --noconfirm --needed unace unrar zip unzip p7zip sharutils uudeview arj cabextract file-roller dtc python-pip brotli axel gawk aria2 detox cpio lz4
    fi
    PIP=pip3
elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install protobuf xz brotli lz4 aria2 detox coreutils p7zip gawk
    PIP=pip
fi

# Create virtual environment and install packages
python3 -m venv .venv
source .venv/bin/activate
"$PIP" install aospdtgen backports.lzma extract-dtb protobuf pycrypto docopt zstandard
