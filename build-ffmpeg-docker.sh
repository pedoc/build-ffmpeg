#!/bin/bash

if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，请先安装 Docker。"
    exit 1
fi

DOCKER_IMAGE="ffmpeg-cross-compile-$(uname -m)"

echo "准备环境,详情: https://docs.docker.com/build/building/multi-platform/"
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --name multiarch-builder --driver docker-container --use|| true
docker buildx use multiarch-builder
docker buildx inspect --bootstrap
docker buildx ls

echo "开始构建"
docker buildx build --build-arg BASE_BUILD_IMAGE=debian:10.13 -f Dockerfile-build-ffmpeg . --platform linux/arm64,linux/amd64 --target bin --output .
#docker buildx build -t $DOCKER_IMAGE -f Dockerfile-build-ffmpeg . --platform linux/arm64 --target build --load

#docker run --rm -it ffmpeg-cross-compile-aarch64 /bin/bash