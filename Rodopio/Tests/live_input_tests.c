#include "../Core/LiveInputCore.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#define PI 3.14159265358979323846
static CRInputReading measure(double rate,double f,int harmonic){
    CRInput *p=cr_input_create(rate);assert(p);
    float data[512];CRInputReading r={0};
    for(int block=0;block<48;block++){
        for(int i=0;i<512;i++){
            double phase=2*PI*f*(block*512+i)/rate;
            data[i]=(float)(harmonic?.12*sin(phase)+.24*sin(2*phase)+.06*sin(3*phase):.25*sin(phase));
        }
        cr_input_push(p,data,512,1);
        if(block%4==3)r=cr_input_read(p);
    }
    cr_input_destroy(p);return r;
}
int main(void){
    assert(!cr_input_create(NAN));assert(!cr_input_create(0));
    const double rates[]={44100,48000,96000};
    const int notes[]={23,28,33,38,43,48,54,59,60,66,69};
    for(unsigned r=0;r<3;r++)for(unsigned n=0;n<sizeof(notes)/sizeof(notes[0]);n++){
        double f=440*pow(2,(notes[n]-69)/12.);
        CRInputReading v=measure(rates[r],f,0);
        assert(v.frequency>0);assert(fabs(1200*log2(v.frequency/f))<20);
        assert(cr_frequency_midi(v.frequency)==notes[n]);assert(v.confidence>.85);
        assert(fabs(v.rms_db-(-15.05))<1.5);
    }
    CRInputReading harmonic=measure(48000,41.2034,1);
    assert(cr_frequency_midi(harmonic.frequency)==28);
    CRInput *p=cr_input_create(48000);float silence[1024]={0};
    for(int i=0;i<10;i++){cr_input_push(p,silence,1024,1);cr_input_read(p);}
    CRInputReading v=cr_input_read(p);assert(v.frequency==0&&v.frames==0);
    float stereo[2048];for(int i=0;i<1024;i++){stereo[i*2]=0;stereo[i*2+1]=1;}
    cr_input_push(p,stereo+1,1024,2);v=cr_input_read(p);assert(v.clipped&&fabs(v.peak_db)<.001);
    for(int i=0;i<40;i++)cr_input_push(p,silence,1024,1);
    v=cr_input_read(p);assert(v.dropped>0&&v.frames<=32768);
    cr_input_destroy(p);
    assert(cr_keyboard_midi(28)==64);assert(cr_keyboard_midi(33)==69);
    assert(cr_keyboard_midi(-1)==-1);assert(cr_frequency_midi(NAN)==-1);
    puts("PASS: live input — bass B0/E1 to A4, 44.1/48/96 kHz, strong harmonic, silence, clipping, stereo stride, overflow, octave mapping.");
}
