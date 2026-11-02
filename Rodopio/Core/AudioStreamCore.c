#include "AudioStreamCore.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#define CAPACITY 16384u
struct CRAudioStream { int16_t samples[CAPACITY]; double times[CAPACITY]; _Atomic uint32_t write, read, dropped; _Atomic int enabled; };
CRAudioStream *cr_stream_create(void) {
    CRAudioStream *s = calloc(1, sizeof(CRAudioStream));
    if (s) { atomic_init(&s->write, 0); atomic_init(&s->read, 0); atomic_init(&s->dropped, 0); atomic_init(&s->enabled, 0); }
    return s;
}
void cr_stream_destroy(CRAudioStream *s) { free(s); }
void cr_stream_enable(CRAudioStream *s, int enabled) { atomic_store(&s->enabled, enabled); }
void cr_stream_push(CRAudioStream *s, const float *data, uint32_t frames, uint32_t stride, double time, double rate) {
    if (!s || !atomic_load_explicit(&s->enabled, memory_order_relaxed) || !data || !stride || rate <= 0) return;
    uint32_t w = atomic_load_explicit(&s->write, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&s->read, memory_order_acquire);
    uint32_t room = CAPACITY - (w-r), count = frames < room ? frames : room;
    for (uint32_t i=0; i<count; i++) {
        float x = data[i*stride]; if (!isfinite(x)) x = 0;
        x = fmaxf(-1, fminf(1, x));
        s->samples[(w+i)%CAPACITY] = (int16_t)lrintf(x*32767.f);
        s->times[(w+i)%CAPACITY] = time + (double)i/rate;
    }
    atomic_store_explicit(&s->write, w+count, memory_order_release);
    if (count < frames) atomic_fetch_add_explicit(&s->dropped, frames-count, memory_order_relaxed);
}
uint32_t cr_stream_read(CRAudioStream *s, int16_t *data, uint32_t capacity, double *time) {
    uint32_t r = atomic_load_explicit(&s->read, memory_order_relaxed);
    uint32_t w = atomic_load_explicit(&s->write, memory_order_acquire);
    uint32_t count = w-r; if (count > capacity) count = capacity;
    if (count && time) *time = s->times[r%CAPACITY];
    for (uint32_t i=0; i<count; i++) data[i] = s->samples[(r+i)%CAPACITY];
    atomic_store_explicit(&s->read, r+count, memory_order_release);
    return count;
}
uint32_t cr_stream_dropped(CRAudioStream *s) { return atomic_load_explicit(&s->dropped, memory_order_relaxed); }
