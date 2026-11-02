#include "NoteDisplay.h"
#include <math.h>
CRNoteDisplay cr_note_display_new(void){return (CRNoteDisplay){-1,-1,0,0,-1};}
void cr_note_display_update(CRNoteDisplay *s,double now,int midi,double frequency,double confidence,double rms){
    if(!s||!isfinite(now))return;
    int valid=midi>=0&&midi<=127&&isfinite(frequency)&&frequency>0&&confidence>=.9&&rms> -52;
    if(valid){
        double expected=s->midi>=0?440*pow(2,(s->midi-69)/12.):0;
        if(s->midi>=0&&fabs(1200*log2(frequency/expected))<65){
            s->frequency+=(frequency-s->frequency)*.2;s->last_valid=now;s->candidate=-1;return;
        }
        if(s->candidate!=midi){s->candidate=midi;s->candidate_since=now;}
        double wait=s->midi<0?.04:.08;
        if(now-s->candidate_since>=wait){s->midi=midi;s->frequency=frequency;s->last_valid=now;s->candidate=-1;return;}
    } else {s->candidate=-1;}
    if(s->midi>=0&&now-s->last_valid>=.35){s->midi=-1;s->frequency=0;}
}
