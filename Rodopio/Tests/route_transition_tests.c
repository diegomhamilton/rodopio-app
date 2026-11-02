#include "../Core/RouteTransition.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    CRRouteWait s=cr_route_wait(10,3);
    assert(cr_route_step(&s,10,1,0,1)==0); /* Old mic is still current. */
    assert(cr_route_step(&s,10.2,1,0,1)==0);
    assert(cr_route_step(&s,10.5,1,1,0)==0); /* USB selected, format not ready. */
    assert(cr_route_step(&s,10.6,1,1,1)==0);
    assert(cr_route_step(&s,10.71,1,1,1)==1);
    s=cr_route_wait(10,3);
    assert(cr_route_step(&s,10.1,0,0,0)==0); /* Enumeration can be transient. */
    assert(cr_route_step(&s,10.4,0,0,0)==-1);
    s=cr_route_wait(10,3);
    assert(cr_route_step(&s,12.9,1,0,1)==0);
    assert(cr_route_step(&s,13,1,0,1)==-2);
    s=cr_route_wait(10,3);
    assert(cr_route_step(&s,10.1,1,1,1)==0);
    assert(cr_route_step(&s,10.15,1,0,1)==0); /* Match oscillation resets stability. */
    assert(cr_route_step(&s,10.2,1,1,1)==0);
    assert(cr_route_step(&s,10.25,1,1,1)==0);
    assert(cr_route_step(&s,10.31,1,1,1)==1);
    puts("PASS: asynchronous USB route wait — delayed selection, delayed format, transient enumeration, unplug, timeout, oscillation.");
}
