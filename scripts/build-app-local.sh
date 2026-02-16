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
-lopencv_video
-L/usr/local/lib/opencv4/3rdparty/ \
-littnotify
-ldl \
-lm \
-lpthread \
-lrt \
-ltegra_hal \
-lkleidicv_hal \
-lkleidicv_thread \
-lkleidicv \
-llibjpeg-turbo \
-llibpng \
-lz \
"

RUNTIME_DYNAMIC_LIBS="-lcamera -lcamera-base"

go build -tags="customenv gocv_specific_modules gocv_video" -ldflags "-extldflags '-Wl,-Bstatic ${OPENCV_STATIC_LIBS} -Wl,-Bdynamic ${RUNTIME_DYNAMIC_LIBS}'" "$@"
