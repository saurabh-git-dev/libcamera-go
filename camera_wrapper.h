// camera_wrapper.h

#ifndef CAMERA_WRAPPER_H
#define CAMERA_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CameraHandle CameraHandle;

int camera_list(char* buffer, int buffer_size);
CameraHandle* camera_open();
int camera_start(CameraHandle* handle);
int camera_frame_width(CameraHandle* handle);
int camera_frame_height(CameraHandle* handle);
int camera_capture(CameraHandle* handle, void* buffer, int buffer_size);
void camera_close(CameraHandle* handle);

#ifdef __cplusplus
}
#endif

#endif
