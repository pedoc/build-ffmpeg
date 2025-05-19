#!/bin/bash

cat source /etc/profile
source /etc/profile
$CC --version
$CXX --version

apt update
apt install sudo cmake autoconf automake make gcc g++ yasm nasm git libtool libtool-bin libarchive-tools wget python3 pkg-config patchelf binutils -y

echo "dbg info"
ldd --version

echo "as info"
as --version

echo "ld info"
ld --version

echo "gcc info"
gcc --version

echo "cpu info"
lscpu

COMP_PKG_NAME=x265
COMP_PKG_DL_NAME=x265_3.6
wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz http://ftp.videolan.org/pub/videolan/x265/$COMP_PKG_DL_NAME.tar.gz
tar -xf $COMP_PKG_DL_NAME.tar.gz
cd $COMP_PKG_DL_NAME/build/linux
cmake -DCMAKE_C_FLAGS="-march=armv8-a" -DCMAKE_CXX_FLAGS="-march=armv8-a" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_BUILD_TYPE=Release -DENABLE_CLI=OFF -DCMAKE_INSTALL_PREFIX=/usr ../../source
make -j$(nproc) && make install