#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_BIN="${OUTPUT_BIN:-libcamera-go-static-opencv}"
OPENCV_PKG="${OPENCV_PKG:-opencv4}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
GO_TAGS="${GO_TAGS:-customenv}"

export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "pkg-config not found" >&2
  exit 1
fi

if ! pkg-config --exists "${OPENCV_PKG}"; then
  echo "${OPENCV_PKG}.pc not found via pkg-config" >&2
  echo "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}" >&2
  exit 1
fi

echo "==> Building app with static OpenCV linker flags"
echo "    project: ${PROJECT_ROOT}"
echo "    output:  ${OUTPUT_BIN}"

export CGO_CPPFLAGS="$(pkg-config --cflags "${OPENCV_PKG}")"
export CGO_CXXFLAGS="${CGO_CPPFLAGS}"
export CGO_LDFLAGS="-Wl,-Bstatic $(pkg-config --libs --static "${OPENCV_PKG}") -Wl,-Bdynamic ${CGO_LDFLAGS:-}"

cd "${PROJECT_ROOT}"
go build -tags "${GO_TAGS}" -o "${OUTPUT_BIN}" .

echo "==> Build complete"
echo "Binary: ${PROJECT_ROOT}/${OUTPUT_BIN}"

if ldd "${PROJECT_ROOT}/${OUTPUT_BIN}" | grep -qi opencv; then
  echo "WARNING: OpenCV shared libraries are still linked dynamically."
  echo "         Install static OpenCV archives (.a) and rebuild."
else
  echo "OpenCV does not appear in ldd output (likely statically linked)."
fi
