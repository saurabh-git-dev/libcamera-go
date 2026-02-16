#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.13.0}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/opencv-static-build}"
JOBS="${JOBS:-$(nproc)}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"
DISABLE_GUI_VIDEO_BACKENDS="${DISABLE_GUI_VIDEO_BACKENDS:-1}"
FORCE_CLEAN="${FORCE_CLEAN:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BUILD_ROOT}/opencv-${OPENCV_VERSION}"
SRC_DIR="${WORK_DIR}/src"
BUILD_DIR="${WORK_DIR}/build"

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "ERROR: root privileges required to run: $*" >&2
    echo "Run as root or install sudo." >&2
    exit 1
  fi
}

echo "==> Building OpenCV ${OPENCV_VERSION} static libraries"
echo "    install prefix: ${INSTALL_PREFIX}"
echo "    work dir:       ${WORK_DIR}"
echo "    disable gui/video backends: ${DISABLE_GUI_VIDEO_BACKENDS}"
echo "    force clean: ${FORCE_CLEAN}"

if [[ "${FORCE_CLEAN}" == "1" ]]; then
  echo "==> Removing existing work dir for fresh rebuild"
  rm -rf "${WORK_DIR}"
fi

if [[ "${INSTALL_DEPS}" == "1" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing build dependencies (apt)"
    run_as_root apt-get update
    if [[ "${DISABLE_GUI_VIDEO_BACKENDS}" == "1" ]]; then
      run_as_root apt-get install -y \
        build-essential cmake pkg-config curl ca-certificates git \
        libjpeg-dev libpng-dev libtiff-dev libopenexr-dev \
        libtbb-dev
    else
      run_as_root apt-get install -y \
        build-essential cmake pkg-config curl ca-certificates git \
        libgtk2.0-dev libavcodec-dev libavformat-dev libswscale-dev \
        libjpeg-dev libpng-dev libtiff-dev libopenexr-dev \
        libtbb-dev libv4l-dev libxvidcore-dev libx264-dev
    fi
  else
    echo "==> Skipping dependency installation (apt-get not found)"
  fi
fi

mkdir -p "${SRC_DIR}" "${BUILD_DIR}"
cd "${SRC_DIR}"

if [[ ! -d "opencv" ]]; then
  echo "==> Cloning OpenCV"
  git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git
elif [[ "${FORCE_CLEAN}" == "1" ]]; then
  echo "==> Refreshing OpenCV source"
  rm -rf opencv
  git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git
fi

# if [[ ! -d "opencv_contrib" ]]; then
#   echo "==> Cloning OpenCV contrib"
#   git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv_contrib.git
# elif [[ "${FORCE_CLEAN}" == "1" ]]; then
#   echo "==> Refreshing OpenCV contrib source"
#   rm -rf opencv_contrib
#   git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv_contrib.git
# fi

echo "==> Configuring CMake"
cd "${BUILD_DIR}"
cmake_args=(
  ../src/opencv
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
  # -DOPENCV_EXTRA_MODULES_PATH="${SRC_DIR}/opencv_contrib/modules"
  -DBUILD_LIST=core,imgproc,imgcodecs,video
  -DBUILD_opencv_dnn=OFF
  -DBUILD_SHARED_LIBS=OFF
  -DENABLE_NEON=ON
  -DOPENCV_GENERATE_PKGCONFIG=ON
  -DBUILD_TESTS=OFF
  -DBUILD_PERF_TESTS=OFF
  -DBUILD_EXAMPLES=OFF
  -DBUILD_opencv_apps=OFF
  -DBUILD_JAVA=OFF
  -DBUILD_opencv_python3=OFF
  -DBUILD_opencv_python2=OFF
)

if [[ "${DISABLE_GUI_VIDEO_BACKENDS}" == "1" ]]; then
  cmake_args+=(
    -DWITH_GTK=OFF
    -DWITH_QT=OFF
    -DWITH_OPENGL=OFF
    -DWITH_FFMPEG=OFF
    -DWITH_GSTREAMER=OFF
    -DWITH_V4L=OFF
    -DWITH_1394=OFF
    -DWITH_JPEG=ON
    -DWITH_PNG=ON
    -DBUILD_JPEG=ON
    -DBUILD_PNG=ON
    -DWITH_TIFF=OFF
    -DWITH_WEBP=OFF
    -DWITH_JASPER=OFF
    -DWITH_OPENJPEG=OFF
    -DWITH_OPENEXR=OFF
    -DWITH_PROTOBUF=OFF
    -DBUILD_PROTOBUF=OFF
    -DWITH_ADE=OFF
  )
fi

cmake "${cmake_args[@]}"

echo "==> Building"
cmake --build . -j "${JOBS}"

echo "==> Installing"
run_as_root cmake --install .

echo "==> Verifying pkg-config"
export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
pkg-config --modversion opencv4
pkg-config --libs --static opencv4

echo "==> Done"