#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

export CGO_ENABLED=1
export CGO_CPPFLAGS="$(pkg-config --cflags opencv4)"

OPENCV_STATIC_LIBS="-L/usr/local/lib \
-lopencv_imgcodecs \
-lopencv_imgproc \
-lopencv_core \
-L/usr/local/lib/opencv4/3rdparty \
-lz \
-lpng \
-ljpeg \
-ldl \
-lm \
-lpthread"

RUNTIME_DYNAMIC_LIBS="-lcamera -lcamera-base"

go build -tags customenv -ldflags "-extldflags '-Wl,-Bstatic ${OPENCV_STATIC_LIBS} -Wl,-Bdynamic ${RUNTIME_DYNAMIC_LIBS}'" "$@"
