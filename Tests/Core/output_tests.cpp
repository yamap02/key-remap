#include "HIDReports.hpp"
#include "OutputQueue.hpp"
#include <cstdlib>
#include <iostream>
#include <thread>
#define CHECK(x) do { if(!(x)) { std::cerr<<"FAIL line "<<__LINE__<<": "<<#x<<'\n';std::abort(); } } while(false)
struct Sink {
    unsigned reports=0;
    template<class T> void async_post_report(const T&) { ++reports; }
};
int main() {
    rekey::HIDReports reports;
    Sink sink;
    // Two physical keyboards holding a shared key must produce one down/up.
    for(auto key : {rekey::key("a"),rekey::key("left_command"),rekey::key("volume_increment"),rekey::key("mission_control"),rekey::key("fn")}) {
        auto before=sink.reports;
        reports.apply(key,true,sink);reports.apply(key,true,sink);
        CHECK(sink.reports==before+1);
        reports.apply(key,false,sink);CHECK(sink.reports==before+1);
        reports.apply(key,false,sink);CHECK(sink.reports==before+2);
        reports.apply(key,false,sink);CHECK(sink.reports==before+2);
    }
    reports.apply(rekey::key("a"),true,sink);
    reports.apply(rekey::key("left_shift"),true,sink);
    reports.apply(rekey::key("mute"),true,sink);
    reports.apply(rekey::key("mission_control"),true,sink);
    reports.apply(rekey::key("fn"),true,sink);
    CHECK(reports.keyboard.keys.exists(4));
    CHECK(reports.keyboard.modifiers.get_raw_value()==2);
    CHECK(reports.consumer.keys.exists(0xe2));
    CHECK(reports.apple_keyboard.keys.exists(0x10));
    CHECK(reports.top_case.keys.exists(3));
    auto before=sink.reports;
    reports.reset(sink);CHECK(sink.reports==before+4);
    CHECK(reports.keyboard.keys.empty() && reports.keyboard.modifiers.empty());
    CHECK(reports.consumer.keys.empty() && reports.apple_keyboard.keys.empty() && reports.top_case.keys.empty());
    reports.apply(4,false,sink);CHECK(sink.reports==before+4);
    reports.apply(4,true,sink);CHECK(sink.reports==before+5);

    rekey::OutputQueue queue;
    for(size_t i=0;i<queue.capacity;++i)CHECK(queue.push({uint32_t(i),true,1}));
    CHECK(!queue.push({}));
    rekey::OutputEvent event;
    for(size_t i=0;i<queue.capacity;++i){CHECK(queue.pop(event));CHECK(event.key==i && event.generation==1);}
    CHECK(!queue.pop(event));
    constexpr uint32_t count=100000;
    std::thread producer([&] { for(uint32_t i=0;i<count;++i)while(!queue.push({i,bool(i%2),i/1000}))std::this_thread::yield(); });
    for(uint32_t i=0;i<count;++i){while(!queue.pop(event))std::this_thread::yield();CHECK(event.key==i && event.down==bool(i%2) && event.generation==i/1000);}
    producer.join();
    std::cout<<"PASS shared-key counts, all four HID report families, release/reset, bounded queue and 100000 concurrent ordered events\n";
}
