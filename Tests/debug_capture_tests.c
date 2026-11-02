#include "../Core/DebugCapture.h"
#include "../Core/NoteDisplay.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
    CRCapture *p=cr_capture_create(48000);assert(p);
    float samples[6000],out[1024];for(int i=0;i<3000;i++){samples[i*2]=0;samples[i*2+1]=(float)i/3000;}
    cr_capture_push(p,samples+1,3000,2,10,0);
    int total=0;CRCaptureBlock b;
    while((b=cr_capture_pop(p,out)).frames){
        assert(fabs(b.host_time-(10+total/48000.))<1e-9);
        for(unsigned i=0;i<b.frames;i++)assert(fabs(out[i]-(float)(total+i)/3000)<1e-6);
        total+=b.frames;
    }
    assert(total==3000);
    for(int i=0;i<300;i++)cr_capture_push(p,samples,1024,1,11+i*1024./48000,1);
    assert(cr_capture_dropped(p)==(300-256)*1024);
    assert(cr_capture_pop(p,out).estimated_time==1);cr_capture_destroy(p);
    CRNoteDisplay s=cr_note_display_new();
    cr_note_display_update(&s,1,28,41.2034,.99,-20);assert(s.midi==-1);
    cr_note_display_update(&s,1.05,28,41.2034,.99,-20);assert(s.midi==28);
    cr_note_display_update(&s,1.1,-1,0,0,-90);assert(s.midi==28);
    cr_note_display_update(&s,1.15,40,82.4068,.99,-20);assert(s.midi==28);
    cr_note_display_update(&s,1.18,28,41.2034,.99,-20);assert(s.midi==28);
    cr_note_display_update(&s,1.2,33,55,.99,-20);assert(s.midi==28);
    cr_note_display_update(&s,1.29,33,55,.99,-20);assert(s.midi==33);
    cr_note_display_update(&s,1.4,-1,0,0,-90);assert(s.midi==33);
    cr_note_display_update(&s,1.7,-1,0,0,-90);assert(s.midi==-1);
    puts("PASS: recording ring samples/timestamps/stereo/overflow; stable note display, dropout hold, octave rejection, valid change and silence.");
}
