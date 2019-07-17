# dumpyara

**Requirements**:
 
      Linux (preferably Ubuntu-based, but Debian is ok)
      Axel
      Brotli
      Protobuf
      7zip
      device-tree-compiler
      rename
      
***For Firmware Extractor (Part of Dumpyara)***:

      apt install liblzma-dev python-pip brotli lz4
      pip install backports.lzma protobuf pycrypto

Usage:
`bash dumpiara_v5_serv.sh "OTAlink" yourGithubToken`

Usage when in already extracted archive:

`git clone https://github.com/xxx/dumpyara.git`

`cd dumpyara`

`bash dumpiara_v5_dropin.sh yourGithubToken`


You can also place your oauth token in a file called `.githubtoken` in the root of this repository, if you wish
It is ignored by git


Before you start, make sure that dumpyara scripts are mapped to your own account and nick, otherwise you'll only dump, not push.

**Supported image types**:

      raw ext4
      sdat
      sdat with Brotli compression
      Android versions up to Pie
      
If you're a member of AndroidDumps org, use a token with following permissions: `admin:org, public_repo`
