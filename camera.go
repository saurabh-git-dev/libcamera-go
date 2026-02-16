package main

/*
#cgo pkg-config: libcamera
#cgo CXXFLAGS: -std=c++17
#include "camera_wrapper.h"
#include <stdlib.h>
*/
import "C"
import (
	"strings"
	"unsafe"
)

func ListCameras() ([]string, int) {
	const bufferSize = 8192
	buffer := C.malloc(C.size_t(bufferSize))
	if buffer == nil {
		return nil, -100
	}
	defer C.free(buffer)

	rc := int(C.camera_list((*C.char)(buffer), C.int(bufferSize)))
	if rc < 0 {
		return nil, rc
	}

	if rc == 0 {
		return []string{}, 0
	}

	raw := C.GoStringN((*C.char)(buffer), C.int(rc))
	lines := strings.Split(raw, "\n")
	result := make([]string, 0, len(lines))
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}

	return result, 0
}

func Open() unsafe.Pointer {
	return unsafe.Pointer(C.camera_open())
}

func Start(handle unsafe.Pointer) int {
	return int(C.camera_start((*C.CameraHandle)(handle)))
}

func FrameWidth(handle unsafe.Pointer) int {
	return int(C.camera_frame_width((*C.CameraHandle)(handle)))
}

func FrameHeight(handle unsafe.Pointer) int {
	return int(C.camera_frame_height((*C.CameraHandle)(handle)))
}

func CaptureFrame(handle unsafe.Pointer, width int, height int) ([]byte, int) {
	if width <= 0 || height <= 0 {
		return nil, -1
	}
	bufferSize := width * height * 3
	buffer := C.malloc(C.size_t(bufferSize))
	if buffer == nil {
		return nil, -2
	}
	defer C.free(buffer)

	rc := int(C.camera_capture(
		(*C.CameraHandle)(handle),
		buffer,
		C.int(bufferSize),
	))
	if rc < 0 {
		return nil, rc
	}

	data := C.GoBytes(buffer, C.int(rc))
	return data, rc
}

func Close(handle unsafe.Pointer) {
	C.camera_close((*C.CameraHandle)(handle))
}
