#include "LiveInputCore.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Input ring requires lock-free unsigned atomics");
#define CAPACITY 32768u
#define WINDOW 1024u
#define FFT_SIZE 2048u
#define MAX_LAG 1024u
struct CRInput {
    _Atomic unsigned write, read, dropped;
    float ring[CAPACITY], history[WINDOW];
    double times[CAPACITY], last_time;
    double real[FFT_SIZE], imag[FFT_SIZE], prefix[WINDOW+1];
    double difference[MAX_LAG+1];
    double sample_rate, sum;
    unsigned decimation, decimation_count, history_count, cursor, last_dropped;
};
CRInput *cr_input_create(double sample_rate) {
    if(!isfinite(sample_rate)||sample_rate<8000||sample_rate>192000)return NULL;
    CRInput *p=calloc(1,sizeof(*p));if(!p)return NULL;
    atomic_init(&p->write,0);atomic_init(&p->read,0);atomic_init(&p->dropped,0);
    p->decimation=(unsigned)(sample_rate/12000.);if(p->decimation<1)p->decimation=1;
    p->sample_rate=sample_rate/p->decimation;return p;
}
void cr_input_destroy(CRInput *p){free(p);}
void cr_input_push_timed(CRInput *p,const float *samples,uint32_t frames,uint32_t stride,double host_time){
    if(!p||!samples||!stride)return;
    unsigned w=atomic_load_explicit(&p->write,memory_order_relaxed);
    const unsigned r=atomic_load_explicit(&p->read,memory_order_acquire);
    unsigned dropped=0;
    for(uint32_t i=0;i<frames;i++){
        if(w-r>=CAPACITY){dropped=frames-i;break;}
        float value=samples[(size_t)i*stride];
        p->ring[w%CAPACITY]=isfinite(value)?value:0.;
        p->times[w%CAPACITY]=host_time>=0?host_time+i/(p->sample_rate*p->decimation):-1;w++;
    }
    atomic_store_explicit(&p->write,w,memory_order_release);
    if(dropped)atomic_fetch_add_explicit(&p->dropped,dropped,memory_order_relaxed);
}
void cr_input_push(CRInput *p,const float *samples,uint32_t frames,uint32_t stride){
    cr_input_push_timed(p,samples,frames,stride,-1);
}
static float history(CRInput *p,unsigned i){return p->history[(p->cursor+i)%WINDOW];}
/* Radix-2 FFT on the analysis thread. Zero padding prevents circular correlation.
   FFT autocorrelation + prefix energies implements variable-overlap YIN differences.
   Frequency comes from interpolated period, not the loudest coarse spectral bin. */
static void fft(double *re,double *im,int inverse){
    for(unsigned i=1,j=0;i<FFT_SIZE;i++){
        unsigned bit=FFT_SIZE>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;
        if(i<j){double t=re[i];re[i]=re[j];re[j]=t;t=im[i];im[i]=im[j];im[j]=t;}
    }
    for(unsigned length=2;length<=FFT_SIZE;length<<=1){
        double angle=(inverse?2:-2)*3.14159265358979323846/length;
        double wr=cos(angle),wi=sin(angle);
        for(unsigned i=0;i<FFT_SIZE;i+=length){
            double ur=1,ui=0;
            for(unsigned j=0;j<length/2;j++){
                unsigned a=i+j,b=a+length/2;
                double vr=re[b]*ur-im[b]*ui,vi=re[b]*ui+im[b]*ur;
                re[b]=re[a]-vr;im[b]=im[a]-vi;re[a]+=vr;im[a]+=vi;
                double next=ur*wr-ui*wi;ui=ur*wi+ui*wr;ur=next;
            }
        }
    }
    if(inverse)for(unsigned i=0;i<FFT_SIZE;i++){re[i]/=FFT_SIZE;im[i]/=FFT_SIZE;}
}
static void pitch(CRInput *p,CRInputReading *out){
    if(p->history_count<WINDOW||out->rms_db < -55.)return;
    unsigned min=(unsigned)(p->sample_rate/500.), max=(unsigned)ceil(p->sample_rate/30.);
    if(min<2)min=2;
    if(max>=MAX_LAG)max=MAX_LAG-1;
    double mean=0;
    for(unsigned i=0;i<WINDOW;i++)mean+=history(p,i);
    mean/=WINDOW;p->prefix[0]=0;
    for(unsigned i=0;i<FFT_SIZE;i++){
        p->real[i]=i<WINDOW?history(p,i)-mean:0;p->imag[i]=0;
        if(i<WINDOW)p->prefix[i+1]=p->prefix[i]+p->real[i]*p->real[i];
    }
    fft(p->real,p->imag,0);
    for(unsigned i=0;i<FFT_SIZE;i++){
        p->real[i]=p->real[i]*p->real[i]+p->imag[i]*p->imag[i];p->imag[i]=0;
    }
    fft(p->real,p->imag,1);
    double cumulative=0.;p->difference[0]=1.;
    for(unsigned tau=1;tau<=max;tau++){
        double d=fmax(0,p->prefix[WINDOW-tau]+p->prefix[WINDOW]-p->prefix[tau]-2*p->real[tau]);
        d/=(WINDOW-tau);
        cumulative+=d;p->difference[tau]=cumulative>1e-20?d*tau/cumulative:1.;
    }
    for(unsigned tau=min;tau<max;tau++){
        if(p->difference[tau]>=.15)continue;
        while(tau+1<max&&p->difference[tau+1]<p->difference[tau])tau++;
        double a=p->difference[tau-1], b=p->difference[tau], c=p->difference[tau+1];
        double denominator=a-2*b+c;
        double correction=fabs(denominator)>1e-12?.5*(a-c)/denominator:0.;
        if(fabs(correction)>1)correction=0;
        double f=p->sample_rate/(tau+correction);
        if(f>=30.&&f<=500.){out->frequency=f;out->confidence=fmax(0,1-b);}return;
    }
}
CRInputReading cr_input_read(CRInput *p){
    CRInputReading out={.rms_db=-120,.peak_db=-120};if(!p)return out;
    unsigned r=atomic_load_explicit(&p->read,memory_order_relaxed);
    const unsigned w=atomic_load_explicit(&p->write,memory_order_acquire);
    double energy=0,peak=0;
    while(r!=w){
        float x=p->ring[r%CAPACITY];p->last_time=p->times[r%CAPACITY];r++;out.frames++;
        energy+=(double)x*x;if(fabs(x)>peak)peak=fabs(x);
        p->sum+=x;p->decimation_count++;
        if(p->decimation_count==p->decimation){
            p->history[p->cursor]=(float)(p->sum/p->decimation);
            p->cursor=(p->cursor+1)%WINDOW;
            if(p->history_count<WINDOW)p->history_count++;
            p->sum=0;p->decimation_count=0;
        }
    }
    atomic_store_explicit(&p->read,r,memory_order_release);
    out.dropped=atomic_load_explicit(&p->dropped,memory_order_relaxed);
    if(!out.frames)return out;
    out.rms_db=20*log10(fmax(1e-6,sqrt(energy/out.frames)));
    out.peak_db=20*log10(fmax(1e-6,peak));out.clipped=peak>=.99;
    if(out.dropped!=p->last_dropped){
        p->last_dropped=out.dropped;p->history_count=0;p->sum=0;p->decimation_count=0;
        return out;
    }
    out.window_seconds=WINDOW/p->sample_rate;
    out.capture_time=p->last_time>=0?p->last_time-out.window_seconds/2:-1;
    pitch(p,&out);return out;
}
int cr_frequency_midi(double f){
    if(!isfinite(f)||f<=0)return -1;
    double note=69.+12.*log2(f/440.);
    if(note<0||note>127)return -1;
    return (int)lround(note);
}
int cr_keyboard_midi(int midi){return midi<0||midi>127?-1:60+midi%12;}
