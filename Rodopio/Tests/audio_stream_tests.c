#include "../Core/AudioStreamCore.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <math.h>
static CRAudioStream *stream;
static _Atomic int done;
static void *producer(void *unused) {
    (void)unused;
    float block[256]; for (int i=0;i<256;i++) block[i]=0.25f;
    for (int i=0;i<4000;i++) cr_stream_push(stream,block,256,1,10.0+(double)(i*256)/48000,48000);
    atomic_store(&done,1); return NULL;
}
int main(void) {
    stream=cr_stream_create(); assert(stream); cr_stream_enable(stream,1);
    pthread_t thread; assert(pthread_create(&thread,NULL,producer,NULL)==0);
    int16_t samples[480]; double time=0, previousEnd=0; uint32_t total=0;
    for (;;) {
        uint32_t count=cr_stream_read(stream,samples,480,&time);
        if (!count) { if (!atomic_load(&done)) continue; count=cr_stream_read(stream,samples,480,&time); if (!count) break; }
        assert(time+1e-9>=previousEnd);
        previousEnd=time+(double)count/48000;
        for (uint32_t i=0;i<count;i++) assert(samples[i]==8192);
        total+=count;
    }
    pthread_join(thread,NULL);
    assert(total+cr_stream_dropped(stream)==4000u*256u);
    cr_stream_destroy(stream);
    puts("PASS: PCM ring concurrent producer/consumer, bounded overflow and timestamps");
}
