#ifndef CR_AUDIO_STREAM_H
#define CR_AUDIO_STREAM_H
#include <stdint.h>
#include <stddef.h>
typedef struct CRAudioStream CRAudioStream;
CRAudioStream *cr_stream_create(void);
void cr_stream_destroy(CRAudioStream *stream);
void cr_stream_enable(CRAudioStream *stream, int enabled);
/* One audio producer, one consumer. No locks or allocation in push. */
void cr_stream_push(CRAudioStream *stream, const float *samples, uint32_t frames, uint32_t stride, double time, double rate);
uint32_t cr_stream_read(CRAudioStream *stream, int16_t *samples, uint32_t capacity, double *time);
uint32_t cr_stream_dropped(CRAudioStream *stream);
#endif
