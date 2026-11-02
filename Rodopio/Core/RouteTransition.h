#ifndef CIRANDA_ROUTE_TRANSITION_H
#define CIRANDA_ROUTE_TRANSITION_H
/* Polling policy only: never sleeps or calls Apple APIs. */
typedef struct { double started, deadline, stable_since; } CRRouteWait;
CRRouteWait cr_route_wait(double now, double timeout);
/* 0 waiting, 1 stable & ready, -1 target removed, -2 timeout */
int cr_route_step(CRRouteWait *state, double now, int available, int matches, int format_ready);
#endif
