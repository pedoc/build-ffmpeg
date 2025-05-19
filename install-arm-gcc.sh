#!/bin/bash

set -e

echo "check package manager and install necessary packages"
if [ -x "$(command -v apt)" ];
then
    PACKAGE_MANAGER="apt"
    apt update
    apt install curl wget xz-utils -y
elif [ -x "$(command -v yum)" ];
then
    PACKAGE_MANAGER="yum"
    yum install -y curl wget xz-utils
else
    echo "unknown package manager"
    PACKAGE_MANAGER="unknown"
fi
if [ "$PACKAGE_MANAGER" = "unknown" ]; then
    echo "Unsupported package manager. Exiting."
    exit 1
fi
echo "PACKAGE_MANAGER: $PACKAGE_MANAGER"

# ========== 参数设置 ==========
VERSION="$1"  # 例如: 13.2.Rel1
if [[ -z "$VERSION" ]]; then
  echo "用法: $0 <版本号> （例如: $0 13.2.Rel1）"
  exit 1
fi

# ARM GCC Base URL 和目标文件名
BASE_URL="https://developer.arm.com/-/media/Files/downloads/gnu/${VERSION}/binrel"
FILENAME="gcc-arm-${VERSION}-aarch64-arm-none-linux-gnueabihf.tar.xz"
DOWNLOAD_URL="${BASE_URL}/${FILENAME}"

# 安装路径
INSTALL_BASE="$HOME/opt/gcc-arm"
INSTALL_DIR="${INSTALL_BASE}/${VERSION}"

# ========== 开始操作 ==========
mkdir -p "$INSTALL_BASE"
cd "$INSTALL_BASE"

echo "[*] 下载 ARM GCC 工具链版本 $VERSION ..."
wget -c "$DOWNLOAD_URL" -O "$FILENAME"

echo "[*] 解压工具链到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
tar -xf "$FILENAME" -C "$INSTALL_DIR" --strip-components=1

# 添加到当前 shell PATH
export PATH="$INSTALL_DIR/bin:$PATH"
export CC="$INSTALL_DIR/bin/arm-none-linux-gnueabihf-gcc"
export CXX="$INSTALL_DIR/bin/arm-none-linux-gnueabihf-g++"

echo "[+] 工具链已设置为当前默认 GCC："
$CC --version
$CXX --version

echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> /etc/profile
echo "export CC=$INSTALL_DIR/bin/aarch64-none-linux-gnu-gcc" >> /etc/profile
echo "export CXX=$INSTALL_DIR/bin/aarch64-none-linux-gnu-g++" >> /etc/profile

cat /etc/profile

echo "gcc info"
gcc --version
g++ --version