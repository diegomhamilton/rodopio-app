#include "DebugCapture.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <math.h>
#define BLOCK 1024u
#define COUNT 256u
_Static_assert(ATOMIC_INT_LOCK_FREE==2,"Requires lock-free ring indices");
struct CRCapture {
    _Atomic unsigned write, read, dropped;
    double sample_rate;
    CRCaptureBlock info[COUNT];
    float data[COUNT][BLOCK];
};
CRCapture *cr_capture_create(double rate){
    if(!isfinite(rate)||rate<8000||rate>192000)return NULL;
    CRCapture *p=calloc(1,sizeof(*p));if(!p)return NULL;
    p->sample_rate=rate;atomic_init(&p->write,0);atomic_init(&p->read,0);atomic_init(&p->dropped,0);return p;
}
void cr_capture_destroy(CRCapture *p){free(p);}
void cr_capture_push(CRCapture *p,const float *x,uint32_t frames,uint32_t stride,double time,int estimated){
    if(!p||!x||!stride||!isfinite(time))return;
    unsigned w=atomic_load_explicit(&p->write,memory_order_relaxed);
    unsigned r=atomic_load_explicit(&p->read,memory_order_acquire);
    for(unsigned offset=0;offset<frames;){
        if(w-r>=COUNT){atomic_fetch_add_explicit(&p->dropped,frames-offset,memory_order_relaxed);break;}
        unsigned n=frames-offset;if(n>BLOCK)n=BLOCK;
        unsigned slot=w%COUNT;
        for(unsigned i=0;i<n;i++)p->data[slot][i]=x[(size_t)(offset+i)*stride];
        p->info[slot]=(CRCaptureBlock){time+(double)offset/p->sample_rate,n,estimated};
        offset+=n;w++;
    }
    atomic_store_explicit(&p->write,w,memory_order_release);
}
CRCaptureBlock cr_capture_pop(CRCapture *p,float *output){
    if(!p||!output)return (CRCaptureBlock){0};
    unsigned r=atomic_load_explicit(&p->read,memory_order_relaxed);
    unsigned w=atomic_load_explicit(&p->write,memory_order_acquire);
    if(r==w)return (CRCaptureBlock){0};
    CRCaptureBlock b=p->info[r%COUNT];
    for(unsigned i=0;i<b.frames;i++)output[i]=p->data[r%COUNT][i];
    atomic_store_explicit(&p->read,r+1,memory_order_release);return b;
}
uint32_t cr_capture_dropped(CRCapture *p){return p?atomic_load_explicit(&p->dropped,memory_order_relaxed):0;}
