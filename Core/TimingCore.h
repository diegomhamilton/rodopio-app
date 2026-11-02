#ifndef TIMING_CORE_H
#define TIMING_CORE_H
#include <stdint.h>
double cr_clock_offset(double t1, double t2, double t3, double t4);
double cr_round_trip(double t1, double t2, double t3, double t4);
int64_t cr_open_bar(double now, double start, double duration, double lead);
double cr_bar_time(int64_t bar, double start, double duration);
int cr_quantize_slot(double gesture, double start, double beat);
#endif
