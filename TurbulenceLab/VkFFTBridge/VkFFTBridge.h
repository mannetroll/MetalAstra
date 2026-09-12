#ifndef TL_FFT_BRIDGE_H
#define TL_FFT_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct TLFFTPlan TLFFTPlan;
TLFFTPlan *TLFFTCreate(void *device, void *queue, void *buffer, uint32_t size, uint32_t batches, uint32_t realTransform, int32_t *error);
int32_t TLFFTAppend(TLFFTPlan *plan, void *commandBuffer, void *encoder, void *buffer, int32_t inverse);
void TLFFTDestroy(TLFFTPlan *plan);
#ifdef __cplusplus
}
#endif

#endif
