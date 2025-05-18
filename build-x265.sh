#!/bin/bash

apt update
apt install sudo cmake autoconf automake make gcc g++ yasm nasm git libtool libtool-bin libarchive-tools wget python3 pkg-config patchelf -y

COMP_PKG_NAME=x265
COMP_PKG_DL_NAME=x265_3.6
wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz http://ftp.videolan.org/pub/videolan/x265/$COMP_PKG_DL_NAME.tar.gz
tar -xf $COMP_PKG_DL_NAME.tar.gz
cd $COMP_PKG_DL_NAME/build/linux
cmake -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_BUILD_TYPE=Release -DENABLE_CLI=OFF -DCMAKE_INSTALL_PREFIX=/usr ../../source
make -j$(nproc) && make install