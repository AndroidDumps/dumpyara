#!/usr/bin/env bash

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Create input & working directory if it does not exist
mkdir -p $PROJECT_DIR/input $PROJECT_DIR/working

# GitHub token
if [[ -n $2 ]]; then
    GIT_OAUTH_TOKEN=$2
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(cat .githubtoken)
else
    echo "GitHub token not found. Dumping just locally..."
fi

# download or copy from local?
if echo "$1" | grep "http" ; then
    URL=$1
    cd $PROJECT_DIR/input
    aria2c -x16 -j$(nproc) ${URL} || wget ${URL} || exit 1
else
    URL=$( realpath "$1" )
fi

ORG=AndroidDumps #your GitHub org name
FILE=${URL##*/}
EXTENSION=${URL##*.}
UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system vendor cust odm oem factory product modem xrom systemex"

if [ -d "$1" ] ; then
    echo 'Directory detected. Copying...'
    cp -a "$1" $PROJECT_DIR/working/${UNZIP_DIR}
elif [ -f "$1" ] ; then
    cp -a "$1" $PROJECT_DIR/input
fi

# clone other repo's
if [ -d "$PROJECT_DIR/Firmware_extractor" ]; then
    git -C $PROJECT_DIR/Firmware_extractor pull --recurse-submodules
else
    git clone -q --recurse-submodules https://github.com/AndroidDumps/Firmware_extractor $PROJECT_DIR/Firmware_extractor
fi
if [ ! -d "$PROJECT_DIR/extract-dtb" ]; then
    git clone -q https://github.com/PabloCastellano/extract-dtb $PROJECT_DIR/extract-dtb
fi
if [ ! -d "$PROJECT_DIR/mkbootimg_tools" ]; then
    git clone -q https://github.com/xiaolu/mkbootimg_tools "$PROJECT_DIR/mkbootimg_tools"
fi

# extract rom via Firmware_extractor
[[ ! -d "$1" ]] && bash $PROJECT_DIR/Firmware_extractor/extractor.sh $PROJECT_DIR/input/${FILE} $PROJECT_DIR/working/${UNZIP_DIR}

# Extract boot.img
python3 $PROJECT_DIR/extract-dtb/extract-dtb.py $PROJECT_DIR/working/${UNZIP_DIR}/boot.img -o $PROJECT_DIR/working/${UNZIP_DIR}/bootimg > /dev/null # Extract boot
bash $PROJECT_DIR/mkbootimg_tools/mkboot $PROJECT_DIR/working/${UNZIP_DIR}/boot.img $PROJECT_DIR/working/${UNZIP_DIR}/boot > /dev/null 2>&1
echo 'boot extracted'

if [[ -f $PROJECT_DIR/working/${UNZIP_DIR}/dtbo.img ]]; then
    python3 $PROJECT_DIR/extract-dtb/extract-dtb.py $PROJECT_DIR/working/${UNZIP_DIR}/dtbo.img -o $PROJECT_DIR/working/${UNZIP_DIR}/dtbo > /dev/null # Extract dtbo
    echo 'dtbo extracted'
fi

# Extract dts
mkdir $PROJECT_DIR/working/${UNZIP_DIR}/bootdts
dtb_list=`find $PROJECT_DIR/working/${UNZIP_DIR}/bootimg -name '*.dtb' -type f -printf '%P\n' | sort`
for dtb_file in $dtb_list; do
    dtc -I dtb -O dts -o $(echo "$PROJECT_DIR/working/${UNZIP_DIR}/bootdts/$dtb_file" | sed -r 's|.dtb|.dts|g') $PROJECT_DIR/working/${UNZIP_DIR}/bootimg/$dtb_file > /dev/null 2>&1
done

# extract PARTITIONS
cd $PROJECT_DIR/working/${UNZIP_DIR}
for p in $PARTITIONS; do
    if [ -e "$p.img" ]; then
        mkdir $p || rm -rf $p/*
        echo "Extracting $p partition"
        7z x $p.img -y -o$p/ 2>/dev/null >> zip.log
        rm $p.img 2>/dev/null
    fi
done
rm zip.log

# board-info.txt
find $PROJECT_DIR/working/${UNZIP_DIR}/modem -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
find $PROJECT_DIR/working/${UNZIP_DIR}/tz* -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
if [ -e $PROJECT_DIR/working/${UNZIP_DIR}/vendor/build.prop ]; then
    strings $PROJECT_DIR/working/${UNZIP_DIR}/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
fi
sort -u -o $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt

#copy file names
chown $(whoami) * -R ; chmod -R u+rwX * #ensure final permissions
find $PROJECT_DIR/working/${UNZIP_DIR} -type f -printf '%P\n' | sort | grep -v ".git/" > $PROJECT_DIR/working/${UNZIP_DIR}/all_files.txt

# set variables
ls system/build*.prop 2>/dev/null || ls system/system/build*.prop 2>/dev/null || { echo "No system build*.prop found, pushing cancelled!" && exit ;}
flavor=$(grep -oP "(?<=^ro.build.flavor=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.vendor.build.flavor=).*" -hs vendor/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.system.build.flavor=).*" -hs {system,system/system}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.build.type=).*" -hs {system,system/system}/build*.prop)
release=$(grep -oP "(?<=^ro.build.version.release=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.vendor.build.version.release=).*" -hs vendor/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.system.build.version.release=).*" -hs {system,system/system}/build*.prop)
id=$(grep -oP "(?<=^ro.build.id=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.vendor.build.id=).*" -hs vendor/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.system.build.id=).*" -hs {system,system/system}/build*.prop)
incremental=$(grep -oP "(?<=^ro.build.version.incremental=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.vendor.build.version.incremental=).*" -hs vendor/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.system.build.version.incremental=).*" -hs {system,system/system}/build*.prop)
tags=$(grep -oP "(?<=^ro.build.tags=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.vendor.build.tags=).*" -hs vendor/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.system.build.tags=).*" -hs {system,system/system}/build*.prop)
fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.vendor.build.fingerprint=).*" -hs vendor/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.system.build.fingerprint=).*" -hs {system,system/system}/build*.prop)
brand=$(grep -oP "(?<=^ro.product.brand=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.vendor.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.vendor.product.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(echo $fingerprint | cut -d / -f1 )
codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.vendor.product.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(echo $fingerprint | cut -d / -f3 | cut -d : -f1 )
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.build.fota.version=).*" -hs {system,system/system}/build*.prop | cut -d - -f1 | head -1)
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build*.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
branch=$(echo $description | tr ' ' '-')
repo=$(echo $brand\_$codename\_dump | tr '[:upper:]' '[:lower:]')
printf "\nflavor: $flavor\nrelease: $release\nid: $id\nincremental: $incremental\ntags: $tags\nfingerprint: $fingerprint\nbrand: $brand\ncodename: $codename\ndescription: $description\nbranch: $branch\nrepo: $repo\n"

if [[ -n $GIT_OAUTH_TOKEN ]] ; then
    curl --silent --fail "https://raw.githubusercontent.com/$ORG/$repo/$branch/all_files.txt" 2>/dev/null && echo "Firmware already dumped!" && exit 1
    git init
    if [ -z "$(git config --get user.email)" ]; then
        git config user.email AndroidDumps@github.com
    fi
    if [ -z "$(git config --get user.name)" ]; then
        git config user.name AndroidDumps
    fi
    git checkout -b $branch
    find -size +97M -printf '%P\n' -o -name *sensetime* -printf '%P\n' -o -name *.lic -printf '%P\n' > .gitignore
    git add --all

    curl -s -X POST -H "Authorization: token ${GIT_OAUTH_TOKEN}" -d '{ "name": "'"$repo"'" }' "https://api.github.com/orgs/${ORG}/repos" #create new repo
    git remote add origin https://github.com/$ORG/${repo,,}.git
    git commit -asm "Add ${description}"
    git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ||

    (git update-ref -d HEAD ; git reset system/ vendor/ ;
    git checkout -b $branch ;
    git commit -asm "Add extras for ${description}" ;
    git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
    git add vendor/ ;
    git commit -asm "Add vendor for ${description}" ;
    git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
    git add system/system/app/ system/system/priv-app/ || git add system/app/ system/priv-app/ ;
    git commit -asm "Add apps for ${description}" ;
    git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
    git add system/ ;
    git commit -asm "Add system for ${description}" ;
    git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;)
else
    echo "Dump done locally."
    exit 1
fi
# Telegram channel
TG_TOKEN=$(cat $PROJECT_DIR/.tgtoken)
if [ ! -z "$TG_TOKEN" ]; then
    CHAT_ID="@android_dumps"
    commit_head=$(git log --format=format:%H | head -n 1)
    commit_link=$(echo "https://github.com/$ORG/$repo/commit/$commit_head")
    echo -e "Sending telegram notification"
    printf "<b>Brand: $brand</b>" > $PROJECT_DIR/working/tg.html
    printf "\n<b>Device: $codename</b>" >> $PROJECT_DIR/working/tg.html
    printf "\n<b>Version:</b> $release" >> $PROJECT_DIR/working/tg.html
    printf "\n<b>Fingerprint:</b> $fingerprint" >> $PROJECT_DIR/working/tg.html
    printf "\n<b>GitHub:</b>" >> $PROJECT_DIR/working/tg.html
    printf "\n<a href=\"$commit_link\">Commit</a>" >> $PROJECT_DIR/working/tg.html
    printf "\n<a href=\"https://github.com/$ORG/$repo/tree/$branch/\">$codename</a>" >> $PROJECT_DIR/working/tg.html
    TEXT=$(cat $PROJECT_DIR/working/tg.html)
    curl -s "https://api.telegram.org/bot${TG_TOKEN}/sendmessage" --data "text=${TEXT}&chat_id=${CHAT_ID}&parse_mode=HTML&disable_web_page_preview=True" > /dev/null
    rm -rf $PROJECT_DIR/working/tg.html
fi
