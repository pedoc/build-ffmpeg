#!/bin/bash

# passed(20250314):openEuler-20.03-LTS-SP3 x86_64 2c4g gcc7.3.0 glibc2.28
# passed(20250524):debian10.13 gcc8.3.0-6 glibc2.28

# shellcheck disable=SC2119
# shellcheck disable=SC2120

# playground
# docker run -itd --name build-ffmpeg -v $(pwd):/app -w /app docker.gh-proxy.com/debian:10.13 /bin/bash
# docker run -d -p 39111:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock docker.gh-proxy.com/portainer/portainer-ce
# docker exec -it build-ffmpeg /bin/bash

set -e

export TZ=Asia/Shanghai
BUILD_AT=$(date "+%Y%m%d-%H%M%S")

COLOR_BLUE=$(tput setaf 4)
COLOR_WHITE=$(tput setaf 7)
COLOR_RED=$(tput setaf 1)
COLOR_YELLOW=$(tput setaf 3)

ARCH=$(uname -m)
ENTRYPOINT_DIR=$(pwd)
echo "ENTRYPOINT_DIR:$ENTRYPOINT_DIR,files:"
ls -lha --color

WORK_DIR="$ENTRYPOINT_DIR/ffmpeg-build"
mkdir -p "$WORK_DIR"

echo "ARCH=$ARCH PATH=$PATH ENTRYPOINT_DIR=$ENTRYPOINT_DIR"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"


info() {
    echo -e "${COLOR_WHITE}[$(date +"%Y-%m-%d %H:%M:%S") INF] $1 $2 $3 $4 $5 ${COLOR_WHITE}"
}

dbg() {
    echo -e "${COLOR_BLUE}[$(date +"%Y-%m-%d %H:%M:%S") DBG] $1 $2 $3 $4 $5 ${COLOR_WHITE}"
}

warn() {
    echo -e "${COLOR_YELLOW}[$(date +"%Y-%m-%d %H:%M:%S") WRN] $1 $2 $3 $4 $5 ${COLOR_WHITE}"
}

err() {
    echo -e "${COLOR_RED}[$(date +"%Y-%m-%d %H:%M:%S") ERR] $1 $2 $3 $4 $5 ${COLOR_WHITE}"
}

info_line () {
    info "----------------- $1 -----------------"
}
warn_line () {
    warn "----------------- $1 -----------------"
}
err_line () {
    err "----------------- $1 -----------------"
}

PROXY_SERVICE=${1-http://192.168.1.2:10808}
FFMPEG_REPO_URL=${2:-https://gitee.com/pedoc/ffmpeg.git}
info_line "PROXY_SERVICE $PROXY_SERVICE"

info_line "cpu info"
lscpu

chk_comp_pkg_config() {
    if pkg-config --exists $1; then
        info_line "$1 in pkgconfig"
    else
        err_line "$1 not in pkgconfig"
        exit 1
    fi
}

wait_for_input() {
    return 0
    local timeout=${1:-60}
    local input=""

    info_line "wait for input, timeout: ${timeout} seconds, press any key to continue"

    if read -t $timeout -n 1 input; then
        info_line "continue build"
        return 0
    fi

    info_line "${timeout} seconds passed, continue build..."
    return 1
}

build_nasm_from_source() {
    wget --no-check-certificate https://www.nasm.us/pub/nasm/stable/nasm-2.16.03.tar.xz
    tar -xvf nasm-2.16.03.tar.xz
    cd nasm-2.16.03
    ./configure
    make -j$(nproc) && make install
}

build_autoconf_from_source() {
    wget --no-check-certificate https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.xz
    tar -xvf autoconf-2.71.tar.xz
    cd autoconf-2.71
    ./configure
    make -j$(nproc) && make install
    cp -rf ./bin/autoconf /usr/bin/
}

install_lddtree_from_pkgforge(){
    cd $WORK_DIR
    if command -v lddtree >/dev/null 2>&1; then
        info_line "lddtree already installed"
        return 0
    else
        echo "lddtree not found"
    fi
    local url="https://pkgs.pkgforge.dev/dl/bincache/${ARCH}-linux/lddtree/official/lddtree/raw.dl"
    info "Downloading lddtree(static) from $url ..."
    local dl_name="lddtree"
    $PC4 wget --no-check-certificate -O $dl_name $url
    chmod +x $dl_name
    mv $dl_name /usr/local/bin/
    info "lddtree install completed"
}

install_cmake3_if_need() {
    local version="3.28.4"
    local install_prefix="/usr/local"
    local url="https://github.com/Kitware/CMake/releases/download/v${version}/cmake-${version}.tar.gz"

    if [[ -n "$1" ]]; then
        install_prefix="$1"
    fi

    # 检查是否已安装 CMake
    if command -v cmake >/dev/null 2>&1; then
        cmake_version=$(cmake --version | head -n 1 | awk '{print $3}')

        # 比较版本
        if [[ "$(printf '%s\n' "$version" "$cmake_version" | sort -V | head -n 1)" == "$version" ]]; then
            info_line "CMake version is >= $version"
            return
        else
            info_line "CMake version is < $version"
        fi
    fi

    local file="cmake-$version-linux-${ARCH}.tar.gz"
    local dir="${file%.tar.gz}"
    local url="https://github.com/Kitware/CMake/releases/download/v${version}/$file"
    info_line "Download cmake from $url"
    $PC4 wget --no-check-certificate -O $file $url
    tar -xzvf $file
    cd $dir
    cp -r * /usr/

    info_line "CMake installation complete!"
    cmake --version
}

# Only set http/s proxy if PROXY_SERVICE is not empty
if [ -n "$PROXY_SERVICE" ]; then
    info_line "Setting http/s proxy to $PROXY_SERVICE"
    export http_proxy=$PROXY_SERVICE
    export https_proxy=$PROXY_SERVICE
else
    info_line "No proxy service specified, skipping http/s proxy configuration"
fi

info_line "check package manager and install necessary packages"
if [ -x "$(command -v apt)" ];
then
    PACKAGE_MANAGER="apt"
    apt update
    apt install sudo cmake autoconf automake make gcc g++ yasm nasm git libtool libtool-bin libarchive-tools wget python3 pkg-config patchelf -y
elif [ -x "$(command -v yum)" ];
then
    PACKAGE_MANAGER="yum"
    yum makecache
    yum install cmake autoconf automake make gcc gcc-c++ pkgconfig yasm nasm git libtool wget python3 libXext-devel patchelf -y
else
    err "unknown package manager"
    PACKAGE_MANAGER="unknown"
fi
if [ "$PACKAGE_MANAGER" = "unknown" ]; then
    err "Unsupported package manager. Exiting."
    exit 1
fi
info_line "PACKAGE_MANAGER: $PACKAGE_MANAGER"

# Only set git proxy if PROXY_SERVICE is not empty
if [ -n "$PROXY_SERVICE" ]; then
    info_line "Setting git proxy to $PROXY_SERVICE"
    git config --global  http.proxy $PROXY_SERVICE
    git config --global  https.proxy $PROXY_SERVICE
else
    info_line "No proxy service specified, skipping git proxy configuration"
fi

install_lddtree_from_pkgforge

# 检查 autoconf 版本
AUTOCONF_VERSION=$(autoconf --version | head -n1 | awk '{print $4}')
if echo "$AUTOCONF_VERSION" | grep -q "2.71"; then
    info_line "Found autoconf version $AUTOCONF_VERSION"
else
    warn_line "autoconf version $AUTOCONF_VERSION is lower than 2.71, building from source"
    cd $WORK_DIR
    build_autoconf_from_source
    # 重新检查版本
    AUTOCONF_VERSION=$(autoconf --version | head -n1 | awk '{print $4}')
    if echo "$AUTOCONF_VERSION" | grep -q "2.71"; then
        info_line "Successfully installed autoconf version $AUTOCONF_VERSION"
    else
        err_line "Failed to install autoconf 2.71, current version is $AUTOCONF_VERSION"
        exit 1
    fi
fi

# Function to install GCC 7.3
install_gcc_7() {
    info_line "Installing GCC 7.3"
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        # For Ubuntu/Debian
        apt install -y software-properties-common
        add-apt-repository -y ppa:ubuntu-toolchain-r/test
        apt update
        apt install -y gcc-7 g++-7
        update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 70
        update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 70
        update-alternatives --set gcc /usr/bin/gcc-7
        update-alternatives --set g++ /usr/bin/g++-7
    elif [ "$PACKAGE_MANAGER" = "yum" ]; then
        # For CentOS/RHEL
        yum install -y centos-release-scl
        yum install -y devtoolset-7
        # Enable devtoolset-7
        info_line "source /opt/rh/devtoolset-7/enable" >> ~/.bashrc
        source /opt/rh/devtoolset-7/enable
    else
        err_line "Unsupported package manager for GCC installation"
        return 1
    fi
    return 0
}

REQUIRED_GCC_VERSION="7.3.0"
CURRENT_GCC_VERSION=$(gcc -dumpfullversion -dumpversion)

if [[ "$ARCH" =~ arm|aarch ]]; then
    REQUIRED_GCC_VERSION=10.5.0
    if [ "$(printf '%s\n' "$REQUIRED_GCC_VERSION" "$CURRENT_GCC_VERSION" | sort -V | head -n1)" != "$REQUIRED_GCC_VERSION" ]; then
        err "Error: GCC version $CURRENT_GCC_VERSION is less than required $REQUIRED_GCC_VERSION on ARM*" >&2
        info_line "Build GCC from source,ENTRYPOINT_DIR:$ENTRYPOINT_DIR, WORKDIR=$(pwd)"
        bash $ENTRYPOINT_DIR/build-gcc.sh $REQUIRED_GCC_VERSION
    fi
else
    REQUIRED_GCC_VERSION="8.3.0"
    if [ "$(printf '%s\n' "$REQUIRED_GCC_VERSION" "$CURRENT_GCC_VERSION" | sort -V | head -n1)" != "$REQUIRED_GCC_VERSION" ]; then
        err "Error: GCC version $CURRENT_GCC_VERSION is less than required $REQUIRED_GCC_VERSION on X64*" >&2
        info_line "Build GCC from source,ENTRYPOINT_DIR:$ENTRYPOINT_DIR, WORKDIR=$(pwd)"
        bash $ENTRYPOINT_DIR/build-gcc.sh $REQUIRED_GCC_VERSION
    fi
fi

info_line "glibc info"
ldd --version

info_line "gcc info"
#echo 'int main() { return 0; }' | g++ -x c++ - -march=armv8-a+sve2 -c -o /dev/null
gcc --version
gcc -Q --help=target
g++ --version

info_line "debug info"
find /usr -name libstdc++.so.6

# Check for yasm or nasm
if command -v yasm >/dev/null 2>&1; then
    ASMTOOL="yasm"
    info_line "Found yasm assembler"
fi
if command -v nasm >/dev/null 2>&1; then
    ASMTOOL="nasm"
    NASM_VERSION=$(nasm -v | awk '{print $3}' | sed 's/[^0-9.]//g')
    if [ "$(echo -e "2.13\n$NASM_VERSION" | sort -V | head -n1)" = "2.13" ]; then
        info_line "Found nasm version $NASM_VERSION"
    else
        info_line "nasm version $NASM_VERSION is too old, building from source"
        cd $WORK_DIR
        build_nasm_from_source
        info_line "Built nasm from source"
    fi
fi

# Check if we have a valid assembler
if [ -z "$ASMTOOL" ]; then
    err_line "No valid assembler found. Please install yasm or nasm version >= 2.13"
    exit 1
fi


info_line "config env"

# 添加 pkg-config 调试函数
debug_pkg_config() {
    local pkg_name=$1
    info_line "Debugging pkg-config for $pkg_name"

    # 显示 PKG_CONFIG_PATH
    info "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

    # 检查包是否存在
    if pkg-config --exists $pkg_name; then
        info "$pkg_name exists in pkg-config"

        # 获取版本信息
        local version=$(pkg-config --modversion $pkg_name)
        info "Version: $version"

        # 获取编译标志
        local cflags=$(pkg-config --cflags $pkg_name)
        info "CFLAGS: $cflags"

        # 获取链接标志
        local libs=$(pkg-config --libs $pkg_name)
        info "LIBS: $libs"

        # 获取静态链接标志
        local static_libs=$(pkg-config --static --libs $pkg_name)
        info "Static LIBS: $static_libs"

        # 查找 .pc 文件位置
        local pc_file=$(find /usr/lib/pkgconfig /usr/lib64/pkgconfig -name "${pkg_name}.pc" 2>/dev/null)
        if [ -n "$pc_file" ]; then
            info "PC file location: $pc_file"
            info "PC file content:"
            cat "$pc_file"
        else
            warn "PC file not found in standard locations"
        fi

        # 检查库文件
        local lib_paths="/usr/lib /usr/lib64"
        info "Searching for library files:"
        for path in $lib_paths; do
            local static_lib="$path/lib${pkg_name}.a"
            local shared_lib="$path/lib${pkg_name}.so"
            if [ -f "$static_lib" ]; then
                info "Static library found: $static_lib"
            fi
            if [ -f "$shared_lib" ]; then
                info "Shared library found: $shared_lib"
            fi
        done
    else
        err "$pkg_name not found in pkg-config"
        info "Searching for .pc file:"
        find /usr -name "${pkg_name}.pc" 2>/dev/null
    fi
}

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/lib64/pkgconfig:$PKG_CONFIG_PATH"

rm -rf $WORK_DIR || true

mkdir -p $WORK_DIR

# Check if proxychains4 is available
if command -v proxychains4 >/dev/null 2>&1; then
    PC4="proxychains4"
    info_line "proxychains4 found, will use it for downloads"
else
    PC4=""
    info_line "proxychains4 not found, will download directly"
fi

info_line "start build ffmpeg"

info_line "start build static deps"
cd $WORK_DIR
#zlib
COMP_PKG_NAME=zlib
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --depth 1 https://github.com/madler/$COMP_PKG_NAME.git
    cd $COMP_PKG_NAME
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#openssl
COMP_PKG_NAME=openssl
COMP_PKG_DL_NAME=openssl-1.1.1w
if ! pkg-config --exists $COMP_PKG_NAME; then
    info_line "build $COMP_PKG_NAME"
    # http://mirrors.ibiblio.org/openssl/source/
    # https://www.openssl.org/source/openssl-1.1.1f.tar.gz
    # https://www.openssl.org/source/openssl-1.1.1k.tar.gz
    # https://www.openssl.org/source/openssl-1.1.1w.tar.gz
    _url="https://github.com/pedoc/openssl/releases/download/1.1.1w/openssl-1.1.1w.tar.gz"
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz $_url || {
        echo "Download error：$COMP_PKG_DL_NAME.tar.gz ($_url), try github"
        _url="https://gitee.com/pedoc/openssl/releases/download/1.1.1w/openssl-1.1.1w.tar.gz"
        $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz $_url
    }
    tar -xf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./config no-shared --prefix=/usr
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

install_cmake3_if_need

cd $WORK_DIR
#x264
COMP_PKG_NAME=x264
COMP_PKG_DL_NAME=x264-stable
if ! pkg-config --exists $COMP_PKG_NAME; then
    info_line "build $COMP_PKG_NAME"
    #git clone --depth=1 https://code.videolan.org/videolan/x264.git
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.gz
    tar -xf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./configure --enable-static --prefix=/usr
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#x265
COMP_PKG_NAME=x265
COMP_PKG_DL_NAME=x265_3.5
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz http://ftp.videolan.org/pub/videolan/x265/$COMP_PKG_DL_NAME.tar.gz
    tar -xf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME/build/linux
    cmake -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_BUILD_TYPE=Release -DENABLE_CLI=OFF -DCMAKE_INSTALL_PREFIX=/usr ../../source
    make -j$(nproc) && make install
    #info "Libs.private: -lstdc++" >> /usr/local/lib/pkgconfig/x265.pc
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libvpx
COMP_PKG_NAME=vpx
COMP_PKG_NAME_ALT=libvpx
COMP_PKG_DL_NAME=
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --depth=1 https://chromium.googlesource.com/webm/$COMP_PKG_NAME_ALT.git
    cd $COMP_PKG_NAME_ALT
    ./configure --enable-vp9-highbitdepth --as=yasm --enable-static --disable-shared --disable-unit-tests --prefix=/usr
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#sdl2
COMP_PKG_NAME=sdl2
COMP_PKG_DL_NAME=SDL2-2.28.4
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz https://github.com/libsdl-org/SDL/releases/download/release-${COMP_PKG_DL_NAME/SDL2-/}/$COMP_PKG_DL_NAME.tar.gz
    tar -xzvf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    # Configure SDL2 with minimal features to reduce dependencies
    ./configure \
        --prefix=/usr \
        --disable-shared \
        --enable-static
        # --disable-video-wayland \
        # --disable-video-rpi \
        # --disable-video-x11 \
        # --disable-video-opengl \
        # --disable-video-opengles \
        # --disable-video-vulkan \
        # --disable-video-metal \
        # --disable-render-metal \
        # --disable-power \
        # --disable-filesystem \
        # --disable-jack \
        # --disable-esd \
        # --disable-pipewire \
        # --disable-pulseaudio \
        # --disable-arts \
        # --disable-nas \
        # --disable-sndio \
        # --disable-fusionsound \
        # --disable-diskaudio \
        # --disable-dummyaudio
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#fdk-aac
COMP_PKG_NAME=fdk-aac
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --depth 1 https://github.com/mstorsjo/$COMP_PKG_NAME.git
    cd $COMP_PKG_NAME
    autoreconf -fiv
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libmp3lame
COMP_PKG_NAME=libmp3lame
COMP_PKG_DL_NAME=lame-3.100
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz https://zenlayer.dl.sourceforge.net/project/lame/lame/3.100/$COMP_PKG_DL_NAME.tar.gz
    tar -zxvf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./configure --enable-static --disable-shared --prefix=/usr
    make -j$(nproc) && make install

    cat > /usr/lib/pkgconfig/$COMP_PKG_NAME.pc <<'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libmp3lame
Description: A high quality MP3 encoder
Version: 3.100
Libs: -L${libdir} -llibmp3lame
Cflags: -I${includedir}
EOF

fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libogg
COMP_PKG_NAME=ogg
COMP_PKG_DL_NAME=libogg-1.3.5
if ! pkg-config --exists $COMP_PKG_NAME; then
    # don't use https, error: OpenSSL: error:1407742E:SSL routines:SSL23_GET_SERVER_HELLO:tlsv1 alert protocol version on centos7.9
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.xz http://downloads.xiph.org/releases/ogg/$COMP_PKG_DL_NAME.tar.xz
    tar -xvf libogg-1.3.5.tar.xz
    cd $COMP_PKG_DL_NAME
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libtheora
COMP_PKG_NAME=theora
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --depth 1 https://gitlab.xiph.org/xiph/$COMP_PKG_NAME.git
    cd $COMP_PKG_NAME
    ./autogen.sh
    ./configure --disable-shared --enable-static --disable-tests --prefix=/usr
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#flac
COMP_PKG_NAME=flac
COMP_PKG_DL_NAME=flac-1.4.3
if ! pkg-config --exists $COMP_PKG_NAME; then
    # don't use https, error: OpenSSL: error:1407742E:SSL routines:SSL23_GET_SERVER_HELLO:tlsv1 alert protocol version on centos7.9
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.xz http://downloads.xiph.org/releases/flac/$COMP_PKG_DL_NAME.tar.xz
    tar -xvf $COMP_PKG_DL_NAME.tar.xz
    cd $COMP_PKG_DL_NAME
    ./configure --disable-shared --enable-static --disable-debug --disable-oggtest --disable-cpplibs --disable-doxygen-docs --with-ogg --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libvorbis
COMP_PKG_NAME=vorbis
COMP_PKG_DL_NAME=libvorbis-1.3.6
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz http://downloads.xiph.org/releases/vorbis/$COMP_PKG_DL_NAME.tar.gz
    tar zxvf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#bzip2/bzlib
COMP_PKG_NAME=bzip2
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --depth 1 https://gitlab.com/bzip2/$COMP_PKG_NAME.git
    cd $COMP_PKG_NAME
    mkdir build && cd build
    cmake -DENABLE_SHARED_LIB=OFF \
          -DENABLE_STATIC_LIB=ON \
          -DENABLE_APP=0 \
          -DENABLE_EXAMPLES=0 \
          -DENABLE_TESTS=0 \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr \
          -DCMAKE_INSTALL_LIBDIR=lib \
          -DBZ2_LIB_SUFFIX="" \
          ..
    make && make install

    # 如果仍然生成了 _static 后缀的库文件，创建符号链接
    if [ -f "/usr/lib/libbz2_static.a" ] && [ ! -f "/usr/lib/libbz2.a" ]; then
        ln -sf /usr/lib/libbz2_static.a /usr/lib/libbz2.a
    fi
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

#libpng
COMP_PKG_NAME=libpng
COMP_PKG_DL_NAME=libpng-1.6.37
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz https://download.sourceforge.net/libpng/$COMP_PKG_DL_NAME.tar.gz
    tar -zxvf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#freetype
COMP_PKG_NAME=freetype2
if ! pkg-config --exists $COMP_PKG_NAME; then
    git clone --recursive https://gitlab.freedesktop.org/freetype/freetype.git
    cd freetype
    git checkout tags/VER-2-13-3 -b build-2.13.3
    ./autogen.sh
    ./configure --disable-shared --enable-static --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
# opus
COMP_PKG_NAME=opus
COMP_PKG_DL_NAME=opus-1.5.2
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz https://ftp.osuosl.org/pub/xiph/releases/opus/$COMP_PKG_DL_NAME.tar.gz
    tar -zxvf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    #rm -rf opus_data-*.tar.gz
    #proxychains4 bash autogen.sh
    autoreconf -fi
    [[ "$ARCH" =~ arm|aarch ]] && OPUS_EXTRA_CONFIG_FLAGS=--enable-fixed-point
    ./configure --enable-static --disable-shared --disable-extra-programs --disable-doc --disable-maintainer-mode --disable-dependency-tracking $OPUS_EXTRA_CONFIG_FLAGS --prefix=/usr
    make -j$(nproc) && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

cd $WORK_DIR
#libopusenc
COMP_PKG_NAME=libopusenc
COMP_PKG_DL_NAME=libopusenc-0.2.1
if ! pkg-config --exists $COMP_PKG_NAME; then
    $PC4 wget --no-check-certificate -O $COMP_PKG_DL_NAME.tar.gz  https://ftp.osuosl.org/pub/xiph/releases/opus/$COMP_PKG_DL_NAME.tar.gz
    tar -zvxf $COMP_PKG_DL_NAME.tar.gz
    cd $COMP_PKG_DL_NAME
    ./configure --disable-shared --enable-static --disable-dependency-tracking --disable-maintainer-mode --disable-examples --disable-doc --prefix=/usr
    make && make install
fi
chk_comp_pkg_config $COMP_PKG_NAME
wait_for_input

info_line "end build static deps"

info_line "start build ffmpeg"
cd $WORK_DIR
#ffmpeg5.1.2,此分支具有对flv-h265的支持
git clone -b n5.1.2 --depth 1 $FFMPEG_REPO_URL
cd ffmpeg

FFMPEG_OUT_TARGET_DIR=/opt/ffmpeg512
rm -rf $FFMPEG_OUT_TARGET_DIR
#make clean

info_line PKG_CONFIG_PATH=$PKG_CONFIG_PATH
./configure --enable-openssl --enable-gpl --enable-nonfree  --enable-version3 --enable-zlib --enable-bzlib \
    --enable-libx264 --enable-libmp3lame  --enable-libfdk-aac --enable-libopus \
    --enable-libfreetype --enable-libvorbis --enable-libtheora --enable-libx265 \
    --enable-ffplay --enable-sdl2  --enable-libvpx --enable-decoder=vp8 --enable-decoder=vp9 \
    --enable-static --disable-shared --disable-debug --disable-doc \
    --pkg-config-flags="--static" --extra-libs="-lpthread -lm -lz" \
    --extra-cflags="-I/usr/include" \
    --extra-ldflags="-L/usr/lib -static-libgcc -static-libstdc++" \
    --extra-version="by-pedoc-$BUILD_AT" \
    --prefix=$FFMPEG_OUT_TARGET_DIR \
    --logfile=configure.log

make -j $(nproc) && make install

info_line "ffmpeg build done"
ls -lha --color $FFMPEG_OUT_TARGET_DIR/bin
$FFMPEG_OUT_TARGET_DIR/bin/ffmpeg -version

info_line "using patchelf adjust rpath"
patchelf --set-rpath '$ORIGIN' $FFMPEG_OUT_TARGET_DIR/bin/ffmpeg
patchelf --set-rpath '$ORIGIN' $FFMPEG_OUT_TARGET_DIR/bin/ffplay
patchelf --set-rpath '$ORIGIN' $FFMPEG_OUT_TARGET_DIR/bin/ffprobe

info_line "deps check (ffmpeg)"
lddtree $FFMPEG_OUT_TARGET_DIR/bin/ffmpeg
info_line "deps check (ffplay)"
lddtree $FFMPEG_OUT_TARGET_DIR/bin/ffplay
info_line "deps check (ffprobe)"
lddtree $FFMPEG_OUT_TARGET_DIR/bin/ffprobe

cd $WORK_DIR
ARCHIVE_FILE=ffmpeg512-$ARCH.tar.gz
tar -czf $ARCHIVE_FILE -C /opt ffmpeg512
info_line "ffmpeg archive done,src dir:$FFMPEG_OUT_TARGET_DIR, archive dir: $(pwd)"
ls -lha $ARCHIVE_FILE

info_line "move $ARCHIVE_FILE to $ENTRYPOINT_DIR"
mv $ARCHIVE_FILE $ENTRYPOINT_DIR
info_line "ENTRYPOINT_DIR files:"
ls -lha --color $ENTRYPOINT_DIR

#tar -czf ffmpeg512-$(uname -m).tar.gz -C /opt ffmpeg512

# Clean up git proxy settings only if they were set
if [ -n "$PROXY_SERVICE" ]; then
    info_line "Cleaning up proxy settings"
    git config --unset-all --global  https.proxy
    git config --unset-all --global  http.proxy

    unset http_proxy
    unset https_proxy
fi