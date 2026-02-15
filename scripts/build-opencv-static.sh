#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.13.0}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/opencv-static-build}"
JOBS="${JOBS:-$(nproc)}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BUILD_ROOT}/opencv-${OPENCV_VERSION}"
SRC_DIR="${WORK_DIR}/src"
BUILD_DIR="${WORK_DIR}/build"

echo "==> Building OpenCV ${OPENCV_VERSION} static libraries"
echo "    install prefix: ${INSTALL_PREFIX}"
echo "    work dir:       ${WORK_DIR}"

if [[ "${INSTALL_DEPS}" == "1" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing build dependencies (apt)"
    sudo apt-get update
    sudo apt-get install -y \
      build-essential cmake pkg-config curl ca-certificates git \
      libgtk2.0-dev libavcodec-dev libavformat-dev libswscale-dev \
      libjpeg-dev libpng-dev libtiff-dev libopenexr-dev \
      libtbb-dev libv4l-dev libxvidcore-dev libx264-dev
  else
    echo "==> Skipping dependency installation (apt-get not found)"
  fi
fi

mkdir -p "${SRC_DIR}" "${BUILD_DIR}"
cd "${SRC_DIR}"

if [[ ! -d "opencv" ]]; then
  echo "==> Cloning OpenCV"
  git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git
fi

if [[ ! -d "opencv_contrib" ]]; then
  echo "==> Cloning OpenCV contrib"
  git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv_contrib.git
fi

echo "==> Configuring CMake"
cd "${BUILD_DIR}"
cmake ../src/opencv \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
  -DOPENCV_EXTRA_MODULES_PATH="${SRC_DIR}/opencv_contrib/modules" \
  -DBUILD_SHARED_LIBS=OFF \
  -DOPENCV_GENERATE_PKGCONFIG=ON \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_opencv_apps=OFF \
  -DBUILD_JAVA=OFF \
  -DBUILD_opencv_python3=OFF \
  -DBUILD_opencv_python2=OFF

echo "==> Building"
cmake --build . -j "${JOBS}"

echo "==> Installing"
sudo cmake --install .

echo "==> Verifying static artifacts"
ls -1 "${INSTALL_PREFIX}"/lib/libopencv_core*.a "${INSTALL_PREFIX}"/lib/libopencv_imgproc*.a "${INSTALL_PREFIX}"/lib/libopencv_highgui*.a

echo "==> Verifying pkg-config"
export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
pkg-config --modversion opencv4
pkg-config --libs --static opencv4

echo "==> Done"
echo "Use scripts/build-app-static-opencv.sh to build this project with static OpenCV linking."
