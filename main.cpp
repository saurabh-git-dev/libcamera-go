#include <libcamera/libcamera.h>
#include <opencv2/opencv.hpp>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include <sys/mman.h>
#include <unistd.h>

using namespace libcamera;

namespace {

struct CaptureContext {
    std::mutex mutex;
    std::condition_variable cv;
    bool done = false;
    Request::Status status = Request::RequestPending;

    void onRequestComplete(Request *request) {
        if (request->status() != Request::RequestComplete &&
            request->status() != Request::RequestCancelled) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(mutex);
            status = request->status();
            done = true;
        }
        cv.notify_one();
    }
};

bool hasSupportedExt(const std::string &path) {
    std::string ext = std::filesystem::path(path).extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return ext == ".png" || ext == ".jpg" || ext == ".jpeg";
}

int listCameras() {
    auto manager = std::make_unique<CameraManager>();
    if (manager->start() != 0) {
        std::cerr << "list cameras failed: cannot start camera manager\n";
        return 1;
    }

    auto cameras = manager->cameras();
    if (cameras.empty()) {
        std::cout << "No cameras found\n";
        manager->stop();
        return 0;
    }

    for (const auto &cam : cameras) {
        std::cout << cam->id() << "\n";
    }

    manager->stop();
    return 0;
}

int captureAndSave(const std::string &output) {
    if (!hasSupportedExt(output)) {
        std::cerr << "unsupported output extension; use .png/.jpg/.jpeg\n";
        return 1;
    }

    auto manager = std::make_unique<CameraManager>();
    if (manager->start() != 0) {
        std::cerr << "camera open failed: cannot start camera manager\n";
        return 1;
    }

    auto cameras = manager->cameras();
    if (cameras.empty()) {
        std::cerr << "camera open failed: no cameras found\n";
        manager->stop();
        return 1;
    }

    std::shared_ptr<Camera> camera = cameras[0];
    if (camera->acquire() != 0) {
        std::cerr << "camera open failed: acquire failed\n";
        manager->stop();
        return 1;
    }

    auto config = camera->generateConfiguration({StreamRole::StillCapture});
    if (!config || config->empty()) {
        std::cerr << "camera start failed: no valid configuration\n";
        camera->release();
        manager->stop();
        return 1;
    }

    StreamConfiguration &streamConfig = config->at(0);
    streamConfig.pixelFormat = formats::RGB888;

    auto validation = config->validate();
    if (validation == CameraConfiguration::Invalid || streamConfig.pixelFormat != formats::RGB888) {
        std::cerr << "camera start failed: RGB888 not available\n";
        camera->release();
        manager->stop();
        return 1;
    }

    if (camera->configure(config.get()) != 0) {
        std::cerr << "camera start failed: configure failed\n";
        camera->release();
        manager->stop();
        return 1;
    }

    Stream *stream = streamConfig.stream();
    if (!stream) {
        std::cerr << "camera start failed: stream missing\n";
        camera->release();
        manager->stop();
        return 1;
    }

    auto allocator = std::make_unique<FrameBufferAllocator>(camera);
    if (allocator->allocate(stream) < 0 || allocator->buffers(stream).empty()) {
        std::cerr << "camera start failed: buffer allocation failed\n";
        camera->release();
        manager->stop();
        return 1;
    }

    CaptureContext ctx;
    camera->requestCompleted.connect(&ctx, &CaptureContext::onRequestComplete);

    if (camera->start() != 0) {
        std::cerr << "camera start failed\n";
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    FrameBuffer *frameBuffer = allocator->buffers(stream)[0].get();

    std::unique_ptr<Request> request = camera->createRequest();
    if (!request || request->addBuffer(stream, frameBuffer) < 0) {
        std::cerr << "capture failed: cannot create/prepare request\n";
        camera->stop();
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    {
        std::lock_guard<std::mutex> lock(ctx.mutex);
        ctx.done = false;
        ctx.status = Request::RequestPending;
    }

    if (camera->queueRequest(request.get()) < 0) {
        std::cerr << "capture failed: queue request failed\n";
        camera->stop();
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    {
        std::unique_lock<std::mutex> lock(ctx.mutex);
        if (!ctx.cv.wait_for(lock, std::chrono::seconds(5), [&ctx] { return ctx.done; })) {
            std::cerr << "capture failed: timeout\n";
            camera->stop();
            camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
            camera->release();
            manager->stop();
            return 1;
        }
        if (ctx.status != Request::RequestComplete) {
            std::cerr << "capture failed: request not complete\n";
            camera->stop();
            camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
            camera->release();
            manager->stop();
            return 1;
        }
    }

    const auto &planes = frameBuffer->planes();
    if (planes.empty()) {
        std::cerr << "capture failed: no planes\n";
        camera->stop();
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    int width = config->at(0).size.width;
    int height = config->at(0).size.height;

    const FrameBuffer::Plane &plane = planes[0];
    void *mapped = mmap(nullptr, plane.length, PROT_READ, MAP_SHARED, plane.fd.get(), 0);
    if (mapped == MAP_FAILED) {
        std::cerr << "capture failed: mmap failed\n";
        camera->stop();
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    cv::Mat src(height, width, CV_8UC3, mapped);
    cv::Mat srcClone = src.clone();
    munmap(mapped, plane.length);

    cv::Mat resized;
    cv::resize(srcClone, resized, cv::Size(640, 480), 0, 0, cv::INTER_LINEAR);

    cv::Mat gray;
    cv::cvtColor(resized, gray, cv::COLOR_RGB2GRAY);

    std::string absOut = std::filesystem::absolute(output).string();
    if (!cv::imwrite(absOut, gray)) {
        std::cerr << "failed to write image\n";
        camera->stop();
        camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
        camera->release();
        manager->stop();
        return 1;
    }

    std::cout << "Saved screenshot: " << absOut << "\n";

    camera->stop();
    camera->requestCompleted.disconnect(&ctx, &CaptureContext::onRequestComplete);
    camera->release();
    manager->stop();
    return 0;
}

} // namespace

int main(int argc, char **argv) {
    std::string output = "screenshot.png";
    bool list = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--list") {
            list = true;
        } else if (arg == "-o" && i + 1 < argc) {
            output = argv[++i];
        } else {
            std::cerr << "Usage: " << argv[0] << " [--list] [-o <output.png|jpg|jpeg>]\n";
            return 1;
        }
    }

    if (list) {
        return listCameras();
    }

    return captureAndSave(output);
}