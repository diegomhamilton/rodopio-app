#include "TimingCore.h"
#include <math.h>
double cr_clock_offset(double a,double b,double c,double d){ return ((b-a)+(c-d))/2.; }
double cr_round_trip(double a,double b,double c,double d){ return (d-a)-(c-b); }
int64_t cr_open_bar(double now,double start,double duration,double lead){
    if(!isfinite(now)||!isfinite(start)||duration<=0||!isfinite(duration)||!isfinite(lead)||lead<0) return -1;
    double candidate=floor((now+lead-start)/duration)+1.;
    return candidate<0?0:(int64_t)candidate;
}
double cr_bar_time(int64_t bar,double start,double duration){return start+bar*duration;}
int cr_quantize_slot(double gesture,double start,double beat){
    if(beat<=0||!isfinite(beat)||!isfinite(gesture)||!isfinite(start)) return -1;
    long long slot=llround((gesture-start)/(beat/4.));
    return (int)((slot%16+16)%16);
}
