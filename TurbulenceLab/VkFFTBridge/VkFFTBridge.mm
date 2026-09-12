#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <Metal/Metal.hpp>
#define VKFFT_BACKEND 5
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "vkFFT.h"
#pragma clang diagnostic pop
#include "VkFFTBridge.h"

struct TLFFTPlan {
    VkFFTApplication app = {};
    MTL::Buffer *buffer = nullptr;
    uint64_t bytes = 0;
};
TLFFTPlan *TLFFTCreate(void *device, void *queue, void *buffer, uint32_t size, uint32_t batches, uint32_t realTransform, int32_t *error) {
    @autoreleasepool {
        auto *plan = new TLFFTPlan();
        plan->buffer = static_cast<MTL::Buffer *>(buffer);
        plan->bytes = uint64_t(size) * size * batches * sizeof(float) * 2;
        VkFFTConfiguration config = {};
        config.FFTdim = 2;
        config.size[0] = size; config.size[1] = size;
        config.numberBatches = batches;
        config.performR2C = realTransform;
        config.device = static_cast<MTL::Device *>(device);
        config.queue = static_cast<MTL::CommandQueue *>(queue);
        config.buffer = &plan->buffer;
        config.bufferSize = &plan->bytes;
        config.normalize = 1;
        auto result = initializeVkFFT(&plan->app, config);
        *error = int32_t(result);
        if (result != VKFFT_SUCCESS) { deleteVkFFT(&plan->app); delete plan; return nullptr; }
        return plan;
    }
}
int32_t TLFFTAppend(TLFFTPlan *plan, void *commandBuffer, void *encoder, void *buffer, int32_t inverse) {
    // The caller supplies one autorelease pool per submitted batch, not per FFT.
    MTL::Buffer *data = static_cast<MTL::Buffer *>(buffer);
    VkFFTLaunchParams launch = {};
    launch.commandBuffer = static_cast<MTL::CommandBuffer *>(commandBuffer);
    launch.commandEncoder = static_cast<MTL::ComputeCommandEncoder *>(encoder);
    launch.buffer = &data;
    return int32_t(VkFFTAppend(&plan->app, inverse ? 1 : -1, &launch));
}
void TLFFTDestroy(TLFFTPlan *plan) {
    if (plan) { @autoreleasepool { deleteVkFFT(&plan->app); delete plan; } }
}
