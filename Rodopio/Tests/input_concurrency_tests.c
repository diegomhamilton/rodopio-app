#include "../Core/LiveInputCore.h"
#include <pthread.h>
#include <stdatomic.h>
#include <assert.h>
#include <sched.h>
#include <stdio.h>
static CRInput *input;
static atomic_int finished;
static unsigned consumed, dropped;
static void *producer(void *unused){
    (void)unused;float data[256]={0};
    for(int i=0;i<10000;i++){cr_input_push(input,data,256,1);if(i%20==0)sched_yield();}
    atomic_store_explicit(&finished,1,memory_order_release);return NULL;
}
static void *consumer(void *unused){
    (void)unused;
    while(!atomic_load_explicit(&finished,memory_order_acquire)){
        CRInputReading r=cr_input_read(input);consumed+=r.frames;sched_yield();
    }
    CRInputReading r=cr_input_read(input);consumed+=r.frames;dropped=r.dropped;return NULL;
}
int main(void){
    input=cr_input_create(48000);assert(input);atomic_init(&finished,0);
    pthread_t p,c;assert(!pthread_create(&p,NULL,producer,NULL));assert(!pthread_create(&c,NULL,consumer,NULL));
    pthread_join(p,NULL);pthread_join(c,NULL);
    assert(consumed+dropped==256u*10000u);
    cr_input_destroy(input);
    printf("PASS: SPSC concurrent input: %u consumed + %u dropped = 2560000 samples\n",consumed,dropped);
}
