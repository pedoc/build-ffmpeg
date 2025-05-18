#!/bin/bash
set -e

ARCH=$(uname -m)
echo "ARCH=$ARCH PATH=$PATH"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

#export http_proxy=http://192.168.1.2:10808
#export https_proxy=http://192.168.1.2:10808

echo "check package manager and install necessary packages"
if [ -x "$(command -v apt)" ];
then
    PACKAGE_MANAGER="apt"
    apt update
    apt install build-essential curl libgmp-dev libmpfr-dev libmpc-dev libisl-dev flex bison texinfo libz-dev wget -y
elif [ -x "$(command -v yum)" ];
then
    PACKAGE_MANAGER="yum"
    yum install -y gcc gcc-c++ make curl gmp-devel mpfr-devel libmpc-devel isl-devel flex bison texinfo zlib-devel wget
else
    echo "unknown package manager"
    PACKAGE_MANAGER="unknown"
fi
if [ "$PACKAGE_MANAGER" = "unknown" ]; then
    echo "Unsupported package manager. Exiting."
    exit 1
fi
echo "PACKAGE_MANAGER: $PACKAGE_MANAGER"

echo "libstdc++.so.6 locations:"
find /usr -name libstdc++.so.6
find /usr -name libstdc++.so.6 -exec strings {} \; | grep GLIBC

echo "gcc locations:"
find /usr -name gcc

#11.1.0 - 11.5.0
GCC_VERSION=${1:-10.5.0}
GCC_DIR=gcc-${GCC_VERSION}
INSTALL_PREFIX=/usr

wget https://ftp.gnu.org/gnu/gcc/${GCC_DIR}/${GCC_DIR}.tar.xz -O ${GCC_DIR}.tar.xz
tar -xf ${GCC_DIR}.tar.xz && cd ${GCC_DIR}

echo "Downloading prerequisites..."
./contrib/download_prerequisites --force

echo "Building"
./configure --prefix=${INSTALL_PREFIX} \
            --disable-dependency-tracking \
            --disable-nls \
            --disable-multilib \
            --enable-default-pie \
            --enable-languages=c,c++
make -j$(nproc)
make install

echo "gcc $GCC_VERSION build done"

echo "libstdc++.so.6 locations:"
find /usr -name libstdc++.so.6
find /usr -name libstdc++.so.6 -exec strings {} \; | grep GLIBC

echo "gcc locations:"
find /usr -name gcc