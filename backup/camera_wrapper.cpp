// camera_wrapper.cpp

#include "camera_wrapper.h"
#include <libcamera/libcamera.h>
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <memory>
#include <string>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

using namespace libcamera;

struct CameraHandle {
    std::unique_ptr<CameraManager> manager;
    std::shared_ptr<Camera> camera;
    std::unique_ptr<CameraConfiguration> config;
    Stream *stream = nullptr;
    std::unique_ptr<FrameBufferAllocator> allocator;
    bool started = false;

    std::mutex mutex;
    std::condition_variable condition;
    bool requestDone = false;
    Request::Status requestStatus = Request::RequestPending;

    void requestComplete(Request *request) {
        if (request->status() != Request::RequestComplete && request->status() != Request::RequestCancelled)
            return;

        {
            std::lock_guard<std::mutex> lock(mutex);
            requestStatus = request->status();
            requestDone = true;
        }

        condition.notify_one();
    }
};

int camera_list(char* buffer, int buffer_size) {
    if (!buffer || buffer_size <= 0) return -1;

    auto manager = std::make_unique<CameraManager>();
    int startResult = manager->start();
    if (startResult != 0) return -2;

    auto cameras = manager->cameras();

    std::string out;
    for (size_t index = 0; index < cameras.size(); ++index) {
        out += cameras[index]->id();
        if (index + 1 < cameras.size()) out += "\n";
    }

    cameras.clear();
    manager->stop();

    if (static_cast<int>(out.size()) + 1 > buffer_size) return -3;

    std::memcpy(buffer, out.c_str(), out.size());
    buffer[out.size()] = '\0';
    return static_cast<int>(out.size());
}

CameraHandle* camera_open() {
    CameraHandle* handle = new CameraHandle;
    handle->manager = std::make_unique<CameraManager>();

    int startResult = handle->manager->start();
    if (startResult != 0) {
        delete handle;
        return nullptr;
    }

    auto cameras = handle->manager->cameras();
    if (cameras.empty()) {
        handle->manager->stop();
        delete handle;
        return nullptr;
    }

    handle->camera = cameras[0];
    if (handle->camera->acquire() != 0) {
        handle->manager->stop();
        delete handle;
        return nullptr;
    }

    return handle;
}

int camera_start(CameraHandle* handle) {
    if (!handle) return -1;
    if (handle->started) return 0;

    handle->config = handle->camera->generateConfiguration({ StreamRole::StillCapture });
    if (!handle->config || handle->config->empty()) return -2;

    StreamConfiguration &streamConfig = handle->config->at(0);
    streamConfig.pixelFormat = formats::RGB888;

    CameraConfiguration::Status validation = handle->config->validate();
    if (validation == CameraConfiguration::Invalid) return -3;
    if (streamConfig.pixelFormat != formats::RGB888) return -4;

    int configureResult = handle->camera->configure(handle->config.get());
    if (configureResult != 0) return -5;

    handle->stream = streamConfig.stream();
    if (!handle->stream) return -6;

    handle->allocator = std::make_unique<FrameBufferAllocator>(handle->camera);
    int allocationResult = handle->allocator->allocate(handle->stream);
    if (allocationResult < 0) return -7;

    if (handle->allocator->buffers(handle->stream).empty()) return -8;

    handle->camera->requestCompleted.connect(handle, &CameraHandle::requestComplete);

    int startResult = handle->camera->start();
    if (startResult != 0) return -9;

    handle->started = true;
    return 0;
}

int camera_frame_width(CameraHandle* handle) {
    if (!handle || !handle->started || !handle->config || handle->config->empty()) return -1;
    return handle->config->at(0).size.width;
}

int camera_frame_height(CameraHandle* handle) {
    if (!handle || !handle->started || !handle->config || handle->config->empty()) return -1;
    return handle->config->at(0).size.height;
}

int camera_capture(CameraHandle* handle, void* buffer, int buffer_size) {
    if (!handle || !buffer || buffer_size <= 0) return -1;
    if (!handle->started) return -2;

    const auto &buffers = handle->allocator->buffers(handle->stream);
    if (buffers.empty()) return -3;

    FrameBuffer *frameBuffer = buffers[0].get();

    std::unique_ptr<Request> request = handle->camera->createRequest();
    if (!request) return -4;
    if (request->addBuffer(handle->stream, frameBuffer) < 0) return -5;

    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        handle->requestDone = false;
        handle->requestStatus = Request::RequestPending;
    }

    if (handle->camera->queueRequest(request.get()) < 0) return -6;

    {
        std::unique_lock<std::mutex> lock(handle->mutex);
        bool completed = handle->condition.wait_for(lock, std::chrono::seconds(5), [handle]() {
            return handle->requestDone;
        });
        if (!completed) return -7;
        if (handle->requestStatus != Request::RequestComplete) return -8;
    }

    if (frameBuffer->planes().empty()) return -9;
    const FrameBuffer::Plane &plane = frameBuffer->planes()[0];

    void *mapped = mmap(nullptr, plane.length, PROT_READ, MAP_SHARED, plane.fd.get(), 0);
    if (mapped == MAP_FAILED) return -10;

    int bytesToCopy = std::min<int>(buffer_size, static_cast<int>(plane.length));
    std::memcpy(buffer, mapped, bytesToCopy);
    munmap(mapped, plane.length);
    return bytesToCopy;
}

void camera_close(CameraHandle* handle) {
    if (!handle) return;

    if (handle->started && handle->camera)
        handle->camera->stop();

    if (handle->camera)
        handle->camera->requestCompleted.disconnect(handle, &CameraHandle::requestComplete);

    handle->allocator.reset();
    handle->config.reset();
    handle->stream = nullptr;

    if (handle->camera) {
        handle->camera->release();
        handle->camera.reset();
    }

    if (handle->manager)
        handle->manager->stop();

    delete handle;
}
