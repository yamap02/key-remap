#pragma once
#include "Keys.hpp"
#include <array>
#include <atomic>
namespace rekey {
struct OutputEvent { Key key=0; bool down=false; uint64_t generation=0; };
// Main run loop produces, output thread consumes. No allocation or blocking
// on the input path. Session generations prevent replay after a reset.
class OutputQueue {
public:
    static constexpr size_t capacity=4096;
    bool push(OutputEvent event) {
        auto w=write.load(std::memory_order_relaxed);
        if(w-read.load(std::memory_order_acquire)>=capacity)return false;
        events[w%capacity]=event;write.store(w+1,std::memory_order_release);return true;
    }
    bool pop(OutputEvent& event) {
        auto r=read.load(std::memory_order_relaxed);
        if(r==write.load(std::memory_order_acquire))return false;
        event=events[r%capacity];read.store(r+1,std::memory_order_release);return true;
    }
private:
    alignas(64) std::atomic<uint64_t> write{0},read{0};
    std::array<OutputEvent,capacity> events{};
};
}
