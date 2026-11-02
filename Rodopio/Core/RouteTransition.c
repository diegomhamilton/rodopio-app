#include "RouteTransition.h"
#include <math.h>
CRRouteWait cr_route_wait(double now, double timeout) {
    return (CRRouteWait){now, now + timeout, -1};
}
int cr_route_step(CRRouteWait *s, double now, int available, int matches, int format_ready) {
    if(!s||!isfinite(now)||now>=s->deadline)return -2;
    if(!available){
        s->stable_since=-1;
        return now-s->started>=.3?-1:0;
    }
    if(!matches||!format_ready){s->stable_since=-1;return 0;}
    if(s->stable_since<0)s->stable_since=now;
    return now-s->stable_since>=.1?1:0;
}
