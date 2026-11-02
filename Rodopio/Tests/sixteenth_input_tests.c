#include "../Core/LiveInputCore.h"
#include <math.h>
#include <stdio.h>
#include <assert.h>
#include <stdint.h>
#define PI 3.14159265358979323846
int main(void){
 const int notes[16]={28,29,33,34,38,40,43,45,23,24,28,33,38,43,28,29};
 const int rates[]={44100,48000,96000};
 double worst=0;unsigned rng=12345;
 for(int rateIndex=0;rateIndex<3;rateIndex++)for(int color=0;color<3;color++){
  int rate=rates[rateIndex],hop=rate/100,total=rate*2;
  CRInput *p=cr_input_create(rate);assert(p);float samples[960];
  int found[16]={0},correct[16]={0};double votes[16][128]={{0}};double phase=0;
  for(int offset=0;offset<total;offset+=hop){
   int count=hop;if(offset+count>total)count=total-offset;
   for(int i=0;i<count;i++){
    double t=(offset+i)/(double)rate;int slot=(int)(t/.125);if(slot>15)slot=15;
    double f=440*pow(2,(notes[slot]-69)/12.);phase+=2*PI*f/rate;
    double envelope=exp(-3*fmod(t,.125));
    rng=rng*1664525u+1013904223u;double noise=((rng>>8)/16777216.-.5)*.006;
    double value=color==0?.25*sin(phase):color==1?.08*sin(phase)+.22*sin(2*phase)+.10*sin(3*phase):.18*sin(2*phase)+.15*sin(3*phase)+.08*sin(4*phase);
    samples[i]=(float)(envelope*value+noise+.015);
   }
   cr_input_push_timed(p,samples,count,1,10+offset/(double)rate);
   CRInputReading r=cr_input_read(p);
   int slot=(int)((offset+count-1)/(double)rate/.125);
   int measured=cr_frequency_midi(r.frequency);
   if(r.confidence>=.85 && measured>=0 && r.capture_time>=10 && r.capture_time<12){
    int classified=(int)((r.capture_time-10)/.125);votes[classified][measured]+=r.confidence;
   }
   if(r.confidence>=.85&&cr_frequency_midi(r.frequency)==notes[slot]){
    if(!found[slot]){double delay=(offset+count)/(double)rate-slot*.125;if(delay>worst)worst=delay;found[slot]=1;}
    if(r.capture_time>=10&&r.capture_time<12){int classified=(int)((r.capture_time-10)/.125);if(classified==slot)correct[slot]++;}
   }
  }
  for(int slot=0;slot<16;slot++){
   if(!found[slot]||!correct[slot])fprintf(stderr,"FAIL rate=%d color=%d slot=%d note=%d found=%d correct=%d\n",rate,color,slot,notes[slot],found[slot],correct[slot]);
   assert(found[slot]&&correct[slot]);
   int winner=0;for(int n=1;n<128;n++)if(votes[slot][n]>votes[slot][winner])winner=n;
   if(winner!=notes[slot])fprintf(stderr,"Vote mismatch rate=%d color=%d slot=%d got=%d expected=%d\n",rate,color,slot,winner,notes[slot]);
   assert(winner==notes[slot]);
  }
  cr_input_destroy(p);
 }
 printf("PASS: 144 sixteenth-note segments at 120 BPM, adjacent bass semitones, B0, strong/missing fundamental, noise/DC, 44.1/48/96 kHz. Worst first-correct delay %.1f ms (synthetic).\n",worst*1000);
}
