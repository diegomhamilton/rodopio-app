#ifndef CIRANDA_LIVE_INPUT_CORE_H
#define CIRANDA_LIVE_INPUT_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct CRInput CRInput;
typedef struct {
    double rms_db, peak_db, frequency, confidence;
    double capture_time, window_seconds; /* window center, monotonic host seconds */
    uint32_t frames, dropped;
    int clipped;
} CRInputReading;
CRInput *cr_input_create(double sample_rate);
void cr_input_destroy(CRInput *input);
/* Single producer: audio tap. Never allocates, locks or waits. */
void cr_input_push(CRInput *input, const float *samples, uint32_t frames, uint32_t stride);
void cr_input_push_timed(CRInput *input, const float *samples, uint32_t frames, uint32_t stride, double host_time);
/* Single consumer: analysis queue, NOT the realtime callback. */
CRInputReading cr_input_read(CRInput *input);
int cr_frequency_midi(double frequency);
int cr_keyboard_midi(int midi);
#ifdef __cplusplus
}
#endif
#endif
