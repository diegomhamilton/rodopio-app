#ifndef CIRANDA_DEBUG_CAPTURE_H
#define CIRANDA_DEBUG_CAPTURE_H
#include <stdint.h>
typedef struct CRCapture CRCapture;
typedef struct { double host_time; uint32_t frames; int estimated_time; } CRCaptureBlock;
CRCapture *cr_capture_create(double sample_rate);
void cr_capture_destroy(CRCapture *capture);
void cr_capture_push(CRCapture *capture, const float *samples, uint32_t frames,
                     uint32_t stride, double host_time, int estimated_time);
/* Consumer supplies space for at least 1024 floats. */
CRCaptureBlock cr_capture_pop(CRCapture *capture, float *output);
uint32_t cr_capture_dropped(CRCapture *capture);
#endif
