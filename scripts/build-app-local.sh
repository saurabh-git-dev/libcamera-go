#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
OUTPUT_BIN="${OUTPUT_BIN:-${PROJECT_ROOT}/libcamera-recorder}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

echo "==> Building app binary"
echo "    project root: ${PROJECT_ROOT}"
echo "    build dir:    ${BUILD_DIR}"
echo "    build type:   ${BUILD_TYPE}"
echo "    output bin:   ${OUTPUT_BIN}"

cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
  -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}"

cmake --build "${BUILD_DIR}" -j "$(nproc)"

cp "${BUILD_DIR}/libcamera_cpp_app" "${OUTPUT_BIN}"
chmod +x "${OUTPUT_BIN}"

echo "==> Build complete"
echo "Binary: ${OUTPUT_BIN}"
