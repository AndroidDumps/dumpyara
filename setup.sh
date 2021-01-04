#!/bin/bash

if [[ "$OSTYPE" == "linux-gnu" ]]; then
    sudo apt install unace unrar zip unzip p7zip-full p7zip-rar sharutils rar uudeview mpack arj cabextract file-roller device-tree-compiler liblzma-dev python3-pip brotli liblz4-tool axel gawk aria2 detox cpio rename
    PIP=pip3
elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install protobuf xz brotli lz4 aria2
    PIP=pip
fi

"$PIP" install backports.lzma protobuf pycrypto docopt zstandard twrpdtgen
