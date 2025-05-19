#!/bin/bash

set -e

# 设置目标目录
INSTALL_DIR="$HOME/opt/gcc-arm"
mkdir -p "$INSTALL_DIR"

# 指定下载页和目标架构
GCC_PAGE="https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads"
ARCH="aarch64"  # arm64 主机对应的架构

# 获取最新版的 gcc-aarch64 链接
echo "[*] 正在查找适用于 $ARCH 的 GCC 工具链下载链接..."
DOWNLOAD_URL=$(curl -sL "$GCC_PAGE" | grep -oP "https://.*?aarch64.*?x86_64.*?tar\.xz" | head -n 1)

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "[!] 未找到合适的 GCC 工具链下载链接"
  exit 1
fi

echo "[*] 下载地址: $DOWNLOAD_URL"

# 提取文件名
FILENAME=$(basename "$DOWNLOAD_URL")

# 下载工具链
echo "[*] 下载中..."
wget -O "$FILENAME" "$DOWNLOAD_URL"

# 解压到目标目录
echo "[*] 解压中..."
tar -xf "$FILENAME" -C "$INSTALL_DIR"

# 获取解压后的目录
EXTRACTED_DIR=$(tar -tf "$FILENAME" | head -1 | cut -d/ -f1)
TOOLCHAIN_DIR="$INSTALL_DIR/$EXTRACTED_DIR"

# 添加到 PATH
echo "[*] 工具链路径: $TOOLCHAIN_DIR/bin"
echo "[*] 正在设置当前 shell 使用该工具链..."

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

# 设置默认 gcc 为工具链的 gcc
export CC="$TOOLCHAIN_DIR/bin/aarch64-none-linux-gnu-gcc"
export CXX="$TOOLCHAIN_DIR/bin/aarch64-none-linux-gnu-g++"

echo "[+] GCC 版本为:"
$CC --version

echo ""
echo "[✔] 工具链安装并配置完成！"
echo "[i] 若要永久使用，请将以下内容加入 ~/.bashrc 或 ~/.zshrc："
echo "export PATH=\"$TOOLCHAIN_DIR/bin:\$PATH\""
echo "export CC=$TOOLCHAIN_DIR"
