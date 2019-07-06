#!/usr/bin/env bash
if [[ -n $1 ]]; then
    GIT_OAUTH_TOKEN=$1
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(cat .githubtoken)
else
    echo "Please provide github oauth token as a parameter or place it in a file called .githubtoken in the root of this repo"
    exit 1
fi
ORG=AndroidDumps #for org support, here can you write your org name
cd ..
for p in system vendor cust odm oem; do
    brotli -d $p.new.dat.br &>/dev/null ; #extract br
    cat $p.new.dat.{0..999} 2>/dev/null >> $p.new.dat #merge split Vivo(?) sdat
    ./dumpyara/sdat2img.py $p.{transfer.list,new.dat,img} &>/dev/null #convert sdat to img
    mkdir $p\_ || rm -rf $p/*
    echo $p 'extracted'
    sudo mount -t ext4 -o loop $p.img $p\_ &>/dev/null || (mv $p.img temp.img && simg2img temp.img $p.img && rm temp.img && sudo mount -t ext4 -o loop $p.img $p\_ &>/dev/null)
    sudo chown $(whoami) $p\_/ -R
    sudo chmod -R u+rwX $p\_/
done
mkdir modem_
sudo mount -t vfat -o loop firmware-update/NON-HLOS.bin modem_/ || sudo mount -t vfat -o loop firmware-update/modem.img modem_/ ||
sudo mount -t vfat -o loop NON-HLOS.bin modem_/ || sudo mount -t vfat -o loop modem.img modem_/ #extract modem
git clone -q https://github.com/xiaolu/mkbootimg_tools
./mkbootimg_tools/mkboot ./boot.img ./bootimg > /dev/null #extract boot
echo 'boot extracted'
for p in system vendor modem cust odm oem; do
        sudo cp -r $p\_ $p/ #copy images
        echo $p 'copied'
        sudo umount $p\_ &>/dev/null #unmount
        rm -rf $p\_
done
#copy file names
sudo chown $(whoami) * -R ; chmod -R u+rwX * #ensure final permissions
find system/ -type f -exec echo {} >> allfiles.txt \;
find vendor/ -type f -exec echo {} >> allfiles.txt \;
find bootimg/ -type f -exec echo {} >> allfiles.txt \;
find modem/ -type f -exec echo {} >> allfiles.txt \;
find cust/ -type f -exec echo {} >> allfiles.txt \;
find odm/ -type f -exec echo {} >> allfiles.txt \;
find oem/ -type f -exec echo {} >> allfiles.txt \;
sort allfiles.txt > all_files.txt
rm allfiles.txt
rm *.dat *.list *.br system.img vendor.img 2>/dev/null #remove all compressed files

ls system/build.prop 2>/dev/null || ls system/system/build.prop 2>/dev/null || { echo "No system build.prop found, pushing cancelled!" && exit ;}
fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs system/build.prop system/system/build.prop)
brand=$(echo $fingerprint | cut -d / -f1  | tr '[:upper:]' '[:lower:]')
codename=$(echo $fingerprint | cut -d / -f3 | cut -d : -f1  | tr '[:upper:]' '[:lower:]')
description=$(grep -oP "(?<=^ro.build.description=).*" -hs system/build.prop system/system/build.prop)
branch=$(echo $description | tr ' ' '-')
repo=$(echo $brand\_$codename\_dump)

user=TadiT7 #set user for github
git init
git config user.name Tadi
git config user.email TadiT7@github.com
git checkout -b $branch
find -size +97M -printf '%P\n' -o -name *sensetime* -printf '%P\n' -o -name *.lic -printf '%P\n' > .gitignore
git add --all
git reset mkbootimg_tools/ META-INF/ file_contexts.bin dumpyara/

curl -s -X POST -H "Authorization: token ${GIT_OAUTH_TOKEN}" -d '{ "name": "'"$repo"'" }' "https://api.github.com/orgs/${ORG}/repos" #Create new repo
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
