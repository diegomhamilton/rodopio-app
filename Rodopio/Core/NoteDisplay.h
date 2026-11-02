#ifndef CIRANDA_NOTE_DISPLAY_H
#define CIRANDA_NOTE_DISPLAY_H
typedef struct {
    int midi, candidate;
    double frequency, candidate_since, last_valid;
} CRNoteDisplay;
CRNoteDisplay cr_note_display_new(void);
void cr_note_display_update(CRNoteDisplay *state,double now,int midi,double frequency,double confidence,double rms_db);
#endif
