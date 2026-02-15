#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_BIN="${OUTPUT_BIN:-main}"
OPENCV_PKG="${OPENCV_PKG:-opencv4}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
GO_TAGS="${GO_TAGS:-customenv}"
OPENCV_MANUAL_LDFLAGS="${OPENCV_MANUAL_LDFLAGS:-}"
OPENCV_DYNAMIC_MODULES="${OPENCV_DYNAMIC_MODULES:-highgui,videoio}"

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

echo "==> Building app with hybrid OpenCV linkage"
echo "    project: ${PROJECT_ROOT}"
echo "    output:  ${OUTPUT_BIN}"
echo "    dynamic OpenCV modules: ${OPENCV_DYNAMIC_MODULES}"

export CGO_CPPFLAGS="$(pkg-config --cflags "${OPENCV_PKG}")"
export CGO_CXXFLAGS="${CGO_CPPFLAGS}"

if [[ -n "${OPENCV_MANUAL_LDFLAGS}" ]]; then
  export CGO_LDFLAGS="${OPENCV_MANUAL_LDFLAGS} ${CGO_LDFLAGS:-}"
else
  opencv_libs="$(pkg-config --libs "${OPENCV_PKG}")"
  opencv_libs="$(echo "${opencv_libs}" | xargs)"

  IFS=',' read -r -a dynamic_modules <<< "${OPENCV_DYNAMIC_MODULES}"

  static_opencv_tokens=""
  dynamic_opencv_tokens=""
  for token in ${opencv_libs}; do
    case "${token}" in
      -lopencv_*)
        module_name="${token#-lopencv_}"
        force_dynamic=0
        for dm in "${dynamic_modules[@]}"; do
          if [[ "${module_name}" == "${dm}" ]]; then
            force_dynamic=1
            break
          fi
        done
        if [[ ${force_dynamic} -eq 1 ]]; then
          dynamic_opencv_tokens+="${token} "
        else
          static_opencv_tokens+="${token} "
        fi
        ;;
      *)
        static_opencv_tokens+="${token} "
        ;;
    esac
  done

  opencv_static_all="$(pkg-config --libs --static "${OPENCV_PKG}")"
  opencv_static_all="${opencv_static_all//-lIconv::Iconv/}"
  opencv_static_all="$(echo "${opencv_static_all}" | xargs)"

  search_paths=()
  for token in ${opencv_static_all}; do
    case "${token}" in
      -L*)
        search_paths+=("${token#-L}")
        ;;
    esac
  done
  search_paths+=(/usr/lib /usr/local/lib /lib /lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu)
  always_dynamic_libs="m pthread rt dl c gcc gcc_s stdc++"

  static_tokens=""
  dynamic_tokens=""

  for token in ${opencv_static_all}; do
    case "${token}" in
      -lopencv_*)
        ;;
      -l*)
        lib_name="${token#-l}"
        for adl in ${always_dynamic_libs}; do
          if [[ "${lib_name}" == "${adl}" ]]; then
            dynamic_tokens+="${token} "
            continue 2
          fi
        done
        static_found=0
        for libdir in "${search_paths[@]}"; do
          if [[ -f "${libdir}/lib${lib_name}.a" ]]; then
            static_found=1
            break
          fi
        done
        if [[ ${static_found} -eq 1 ]]; then
          static_tokens+="${token} "
        else
          if [[ "${token}" == "-lopenjp2" ]]; then
            if [[ -f /lib/aarch64-linux-gnu/libopenjp2.so.7 ]]; then
              dynamic_tokens+="-l:libopenjp2.so.7 "
              continue
            fi
          fi
          dynamic_tokens+="${token} "
        fi
        ;;
      *)
        static_tokens+="${token} "
        dynamic_tokens+="${token} "
        ;;
    esac
  done

  static_opencv_tokens="$(echo "${static_opencv_tokens}" | xargs)"
  dynamic_opencv_tokens="$(echo "${dynamic_opencv_tokens}" | xargs)"
  static_tokens="$(echo "${static_tokens}" | xargs)"
  dynamic_tokens="$(echo "${dynamic_tokens}" | xargs)"
  extra_dynamic="-l:liblzma.so.5 -l:libbz2.so.1.0 -l:libzstd.so.1 -l:libLerc.so.4 -l:libjbig.so.0 -l:libdeflate.so.0"

  media_ui_dynamic=""
  for dep_pkg in \
    gtk+-2.0 gdk-2.0 glib-2.0 gobject-2.0 gthread-2.0 \
    libavcodec libavformat libavutil libswscale libswresample libavfilter libavdevice \
    gstreamer-1.0 gstreamer-base-1.0 gstreamer-app-1.0 gstreamer-video-1.0; do
    if pkg-config --exists "${dep_pkg}"; then
      media_ui_dynamic+="$(pkg-config --libs "${dep_pkg}") "
    fi
  done
  media_ui_dynamic="$(echo "${media_ui_dynamic}" | xargs)"

  export CGO_LDFLAGS="-Wl,-Bstatic -Wl,--start-group ${static_opencv_tokens} ${static_tokens} -Wl,--end-group -Wl,-Bdynamic ${dynamic_opencv_tokens} ${dynamic_tokens} ${media_ui_dynamic} ${extra_dynamic} ${CGO_LDFLAGS:-}"
fi

cd "${PROJECT_ROOT}"
go build -buildvcs=false -tags "${GO_TAGS}" -o "${OUTPUT_BIN}" .

echo "==> Build complete"
echo "Binary: ${PROJECT_ROOT}/${OUTPUT_BIN}"

opencv_ldd="$(ldd "${PROJECT_ROOT}/${OUTPUT_BIN}" | grep -Ei 'opencv|libcamera' || true)"
echo "${opencv_ldd}"

if echo "${opencv_ldd}" | grep -Eiq 'libopencv_(highgui|videoio)'; then
  echo "Hybrid check: libopencv_highgui/videoio are dynamically linked as expected."
else
  echo "WARNING: expected libopencv_highgui/videoio dynamic links were not found."
fi
