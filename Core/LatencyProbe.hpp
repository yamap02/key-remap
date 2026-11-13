#pragma once
#include "Keys.hpp"
#include <algorithm>
#include <array>
#include <cstdint>

namespace rekey {
// Main-loop owned. Pairs each output sent for a physical input with the value
// the virtual keyboard reports for it. Both times are kernel HID timestamps in
// nanoseconds, so the delta covers the whole physical-to-virtual path.
class LatencyProbe {
public:
    static constexpr uint64_t stale_ns=100'000'000,bucket_ns=10'000;
    static constexpr size_t buckets=1000; // 10 ms; slower samples go to the last bucket.
    struct Summary { uint64_t samples=0,p50_ns=0,p99_ns=0,max_ns=0,unmatched=0; };

    void sent(Key key,bool down,uint64_t input_ns) {
        auto& p=pending[write++%pending.size()];
        if(p.valid)++unmatched;
        p={key,down,input_ns,true};
    }
    void observed(Key key,bool down,uint64_t output_ns) {
        Pending* hit=nullptr;
        for(auto& p:pending) {
            if(!p.valid)continue;
            // An output that changed no report (another device already holds
            // the key) never comes back; drop it before it pairs with a later press.
            if(output_ns>p.time && output_ns-p.time>stale_ns){p.valid=false;++unmatched;continue;}
            if(p.key==key && p.down==down && p.time<=output_ns && (!hit || p.time<hit->time))hit=&p;
        }
        if(!hit)return;
        hit->valid=false;
        auto delta=output_ns-hit->time;
        ++histogram[std::min<uint64_t>(delta/bucket_ns,buckets)];++samples;max=std::max(max,delta);
    }
    // Outputs queued before a reset are discarded by the output thread.
    void clear() { for(auto& p:pending)p.valid=false; }
    Summary take() {
        Summary s{samples,0,0,max,unmatched};
        auto percentile=[&](uint64_t rank) {
            uint64_t seen=0;
            for(size_t i=0;i<buckets;++i){seen+=histogram[i];if(seen>=rank)return std::min<uint64_t>((i+1)*bucket_ns,max);}
            return max;
        };
        if(samples){s.p50_ns=percentile((samples+1)/2);s.p99_ns=percentile((samples*99+99)/100);}
        histogram={};samples=0;max=0;unmatched=0;
        return s;
    }
private:
    struct Pending { Key key=0;bool down=false;uint64_t time=0;bool valid=false; };
    std::array<Pending,64> pending{};size_t write=0;
    std::array<uint32_t,buckets+1> histogram{};uint64_t samples=0,max=0,unmatched=0;
};
}
