#!/usr/bin/env bash
URL=$1
if [[ -n $2 ]]; then
    GIT_OAUTH_TOKEN=$2
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(cat .githubtoken)
else
    echo "Please provide github oauth token as a parameter or place it in a file called .githubtoken in the root of this repo"
    exit 1
fi
ORG=AndroidDumps #for orgs support, here can write your org name
axel -a -n64 ${URL:?} #download rom
FILE=${URL##*/}
EXTENSION=${URL##*.}
UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system vendor cust odm oem modem"

if [ -d "${HOME}/Firmware_extractor" ]; then
    git -C ~/Firmware_extractor pull --recurse-submodules
else
    git clone --recurse-submodules https://github.com/AndroidDumps/Firmware_extractor ~/Firmware_extractor
fi
~/Firmware_extractor/extractor.sh ${FILE} ${UNZIP_DIR}

cd ${UNZIP_DIR}

for p in $PARTITIONS; do
    mkdir $p || rm -rf $p/*
    echo $p 'extracted'
    7z x $p.img -y -o$p/ 2>/dev/null >> zip.log
    rm $p.img 2>/dev/null
done
rm zip.log

if [[ ! -d "${HOME}/extract-dtb" ]]; then
    cd
    git clone https://github.com/PabloCastellano/extract-dtb
    cd -
fi
python3 ~/extract-dtb/extract-dtb.py ./boot.img -o ./bootimg > /dev/null # Extract boot
echo 'boot extracted'

if [[ -f dtbo.img ]]; then
    python3 ~/extract-dtb/extract-dtb.py ./dtbo.img -o ./dtbo > /dev/null # Extract dtbo
    echo 'dtbo extracted'
fi

# Extract dts
mkdir bootdts
dtb_list=`find bootimg -name '*.dtb' -type f -printf '%P\n' | sort`
for dtb_file in $dtb_list; do
	echo -e "Extracting dts from $dtb_file"
	dtc -I dtb -O dts -o bootdts/$dtb_file bootimg/$dtb_file > /dev/null 2>&1
	mv bootdts/$dtb_file $(echo "bootdts/$dtb_file" | sed -r 's|.dtb|.dts|g')
done

# board-info.txt
find . -type f -name "modem.img" -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS.AT." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.AT.|require version-baseband=|g" >> board-info.txt
find . -type f -name "tz.img" -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> board-info.txt
if [ -e vendor/build.prop ]; then
	strings vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> board-info.txt
fi
sort -u -o board-info.txt board-info.txt

#copy file names
sudo chown $(whoami) * -R ; chmod -R u+rwX * #ensure final permissions
for p in $PARTITIONS; do
    if [[ -d $p ]]; then
        find $p/ -type f -exec echo {} >> allfiles.txt \;
    fi
done
find bootimg/ -type f -exec echo {} >> allfiles.txt \;

sort allfiles.txt > all_files.txt
rm allfiles.txt

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
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(echo $fingerprint | cut -d / -f1 )
codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(echo $fingerprint | cut -d / -f3 | cut -d : -f1 )
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build*.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
branch=$(echo $description | tr ' ' '-')
repo=$(echo $brand\_$codename\_dump | tr '[:upper:]' '[:lower:]')

user=TadiT7 #set user for github
git init
git config user.name Tadi
git config user.email TadiT7@github.com
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
