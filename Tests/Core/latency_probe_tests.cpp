#include "LatencyProbe.hpp"
#include <cassert>
#include <iostream>

int main() {
    {
        rekey::LatencyProbe probe;
        probe.sent(4,true,1'000'000);probe.observed(4,true,1'250'000);
        probe.sent(4,false,2'000'000);probe.observed(4,false,2'500'000);
        auto s=probe.take();
        assert(s.samples==2 && s.max_ns==500'000 && s.unmatched==0);
        assert(s.p50_ns==260'000 && s.p99_ns==500'000); // Bucket upper bound, capped by the maximum.
        assert(probe.take().samples==0); // take() starts a new window.
    }
    {
        // A late callback still pairs: staleness is judged by the virtual timestamp.
        rekey::LatencyProbe probe;
        probe.sent(4,true,1'000'000);probe.observed(4,true,1'300'000);
        assert(probe.take().samples==1);
    }
    {
        // An output that never reaches the virtual keyboard is dropped once
        // stale instead of pairing with the next press of the same key.
        rekey::LatencyProbe probe;
        probe.sent(4,true,0);
        probe.sent(4,true,200'000'000);probe.observed(4,true,200'100'000);
        auto s=probe.take();
        assert(s.samples==1 && s.max_ns==100'000 && s.unmatched==1);
    }
    {
        // Direction and key both have to match; the oldest pending entry wins.
        rekey::LatencyProbe probe;
        probe.sent(224,true,1'000);probe.sent(4,true,2'000);
        probe.observed(4,false,3'000);
        probe.observed(4,true,5'000);probe.observed(224,true,9'000);
        auto s=probe.take();
        assert(s.samples==2 && s.max_ns==8'000);
    }
    {
        rekey::LatencyProbe probe;
        probe.sent(4,true,0);probe.clear();probe.observed(4,true,10);
        assert(probe.take().samples==0);
    }
    {
        // Samples beyond the histogram range still report their real maximum.
        rekey::LatencyProbe probe;
        probe.sent(4,true,0);probe.observed(4,true,20'000'000);
        auto s=probe.take();
        assert(s.p50_ns==20'000'000 && s.p99_ns==20'000'000 && s.max_ns==20'000'000);
    }
    std::cout<<"latency probe tests passed\n";
}
