#include "../Core/TimingCore.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
    assert(fabs(cr_clock_offset(10,15.05,15.06,10.11)-5)<1e-9);
    assert(fabs(cr_round_trip(10,15.05,15.06,10.11)-.1)<1e-9);
    assert(cr_open_bar(8,10,2,.5)==0);
    assert(cr_open_bar(9.499,10,2,.5)==0);
    assert(cr_open_bar(9.5,10,2,.5)==1);
    assert(cr_open_bar(11.5,10,2,.5)==2);
    assert(cr_open_bar(10,10,0,.5)==-1);
    assert(cr_quantize_slot(10.26,10,.5)==2);
    assert(cr_quantize_slot(11.99,10,.5)==0);
    assert(cr_quantize_slot(9.75,10,.5)==14);
    for(int bpm=60;bpm<=200;bpm+=5){
        double beat=60./bpm;
        for(int slot=0;slot<16;slot++){
            assert(cr_quantize_slot(10+slot*beat/4,10,beat)==slot);
            assert(cr_quantize_slot(10+slot*beat/4+.01,10,beat)==slot);
        }
        /* A pitch voice is reused every 4 slots, after its 160ms release. */
        assert(4*(beat/4)>.16);
    }
    assert(cr_quantize_slot(10.06249,10,.5)==0);
    assert(cr_quantize_slot(10.06251,10,.5)==1);
    assert(cr_quantize_slot(11.875,10,.5)==15);
    for(int i=0;i<100000;i++){
        double now=8+i*.001;
        int64_t bar=cr_open_bar(now,10,2,.5);
        assert(cr_bar_time(bar,10,2)-.5>now-1e-10);
        if(bar>0) assert(cr_bar_time(bar-1,10,2)-.5<=now+1e-10);
    }
    puts("PASS: clock, deadline boundary, late assignment, quantization; 100000 timeline cases");
}
