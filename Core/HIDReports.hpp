#pragma once
#include "Keys.hpp"
#include <array>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>

namespace rekey {
namespace hid_report = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;

// Owned by the output thread. A key shared by multiple devices stays down
// until every device has released it.
class HIDReports {
    std::array<uint16_t, max_keys> counts{};
public:
    hid_report::keyboard_input keyboard;
    hid_report::consumer_input consumer;
    hid_report::apple_vendor_keyboard_input apple_keyboard;
    hid_report::apple_vendor_top_case_input top_case;

    void clear() {
        counts = {};
        keyboard = {}; consumer = {}; apple_keyboard = {}; top_case = {};
    }
    template<class Sink> void reset(Sink& sink) {
        clear();
        sink.async_post_report(keyboard); sink.async_post_report(consumer);
        sink.async_post_report(apple_keyboard); sink.async_post_report(top_case);
    }
    template<class Sink> void apply(Key key, bool down, Sink& sink) {
        const auto index = slot(key);
        if(index >= counts.size()) return;
        auto& count = counts[index];
        bool change = false;
        if(down) { if(count < 65535) change = count++ == 0; }
        else if(count) change = --count == 0;
        if(!change) return;
        if(key >= 224 && key <= 231) {
            auto mod = static_cast<hid_report::modifier>(1 << (key - 224));
            if(down) keyboard.modifiers.insert(mod); else keyboard.modifiers.erase(mod);
            sink.async_post_report(keyboard);
        } else if(key < 256) {
            if(down) keyboard.keys.insert(key); else keyboard.keys.erase(key);
            sink.async_post_report(keyboard);
        } else if((key >> 16) == 0xff01) {
            if(down) apple_keyboard.keys.insert(key & 65535); else apple_keyboard.keys.erase(key & 65535);
            sink.async_post_report(apple_keyboard);
        } else if((key >> 16) == 0xff) {
            if(down) top_case.keys.insert(key & 65535); else top_case.keys.erase(key & 65535);
            sink.async_post_report(top_case);
        } else if((key >> 16) == 12) {
            if(down) consumer.keys.insert(key & 65535); else consumer.keys.erase(key & 65535);
            sink.async_post_report(consumer);
        }
    }
};
}
