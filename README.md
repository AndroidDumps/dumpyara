# dumpyara

**Requirements**:
 
      Linux (preferably Ubuntu-based, but Debian is ok)
      Axel
      Brotli
      Protobuf
      7zip
      device-tree-compiler
      
***For Firmware Extractor (Part of Dumpyara)***:

      apt install liblzma-dev python-pip brotli lz4
      pip install backports.lzma protobuf pycrypto

Usage:
`bash dumpyara.sh "<OTAlink> OR <OTA file path>" yourGithubToken`


You can also place your oauth token in a file called `.githubtoken` in the root of this repository, if you wish
It is ignored by git


Before you start, make sure that dumpyara scripts are mapped to your own account and nick, otherwise you'll only dump, not push.

**Supported image types**:

      raw ext4
      sdat
      sdat with Brotli compression
      Android versions up to Pie
      
If you're a member of AndroidDumps org, use a token with following permissions: `admin:org, public_repo`
