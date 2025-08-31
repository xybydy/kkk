#!/bin/sh

function git_clone_path() {
  trap 'rm -rf "$tmpdir"' EXIT
  branch="$1" rurl="$2" mv="$3"
  [[ "$mv" != "mv" ]] && shift 2 || shift 3
  rootdir="$PWD"
  tmpdir="$(mktemp -d)" || exit 1
  if [ ${#branch} -lt 10 ]; then
    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$rurl" "$tmpdir"
    cd "$tmpdir"
  else
    git clone --filter=blob:none --sparse "$rurl" "$tmpdir"
    cd "$tmpdir"
    git checkout $branch
  fi
  if [ "$?" != 0 ]; then
    echo "error on $rurl"
    exit 1
  fi
  git sparse-checkout init --cone
  git sparse-checkout set $@
  [[ "$mv" != "mv" ]] && cp -rn ./* $rootdir/ || mv -n $@/* $rootdir/$@/
  cd $rootdir
}


TARGET="armsr_armv8" # rockchip_armv8
REPO_BRANCH="openwrt-24.10"

sed -i "1a TARGET=${TARGET}" diy.sh

if [ "$TARGET" = "rockchip_armv8" ]; then
    export MTARGET=aarch64_generic
elif [ "$TARGET" = "armsr_armv8" ]; then
    export MTARGET=aarch64_cortex-a53
fi

git clone https://github.com/openwrt/openwrt -b $REPO_BRANCH openwrt


cd openwrt

chmod +x ../diy.sh
/bin/bash ../diy.sh

cp -f ../.config .config

if [ -f ../${{TARGET}}/.config ]; then
    echo >> .config
    cat ../${TARGET}/.config >> .config
fi

if [ -f ../${TARGET}/diy.sh ]; then
    chmod +x ../${TARGET}/diy.sh
    /bin/bash ../${TARGET}/diy.sh
fi

cp -Rf ./diy/* ./ || true

## apply patch

cp -rn ../patches ../${TARGET}/

if [ -n "$(ls -A ../${TARGET}/*.bin.patch 2>/dev/null)" ]; then
  git apply ../${TARGET}/patches/*.bin.patch
fi

find "../${TARGET}/patches" -maxdepth 1 -type f -name '*.revert.patch' -print0 | sort -z | xargs -I % -t -0 -n 1 sh -c "cat '%'  | patch -d './' -R -B --merge -p1 --forward"
find "../${TARGET}/patches" -maxdepth 1 -type f -name '*.patch' ! -name '*.revert.patch' ! -name '*.bin.patch' -print0 | sort -z | xargs -I % -t -0 -n 1 sh -c "cat '%'  | patch -d './' -B --merge -p1 --forward"

sed -i '$a  \
CONFIG_CPU_FREQ_GOV_POWERSAVE=y \
CONFIG_CPU_FREQ_GOV_USERSPACE=y \
CONFIG_CPU_FREQ_GOV_ONDEMAND=y \
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y \
CONFIG_CRYPTO_CHACHA20_NEON=y \
CONFIG_CRYPTO_CHACHA20POLY1305=y \
CONFIG_FAT_DEFAULT_IOCHARSET="utf8" \
' `find target/linux -path "target/linux/*/config-*"`


# defconfig

make defconfig
shopt -s extglob
make download -j$(nproc)
make -j$(($(nproc)+1))