#pragma once
#include "HIDReports.hpp"
#include "OutputQueue.hpp"
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <semaphore>
#include <thread>
#include <os/log.h>

namespace rekey {
class VirtualHIDOutput {
    OutputQueue queue;
    std::atomic<bool> driver_ready{false},accepting{false},running{true};
    std::atomic<uint64_t> generation{1},heartbeat_ns{0};
    std::counting_semaphore<> wake{0};
    os_log_t log;
    std::thread worker;
    static uint64_t now() { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

    void driverState(bool ready) {
        // Status responses include all fields; repeated ready=false must not
        // create a reset -> failed send -> reset feedback loop while offline.
        if(driver_ready.exchange(ready)==ready)return;
        accepting.store(false);
        generation.fetch_add(1);
        wake.release();
    }
    void run() {
        namespace service=pqrs::karabiner::driverkit::virtual_hid_device_service;
        service::client client;
        client.connected.connect([&] {
            service::virtual_hid_keyboard_parameters p;
            p.set_country_code(pqrs::hid::country_code::us);
            client.async_virtual_hid_keyboard_initialize(p);
        });
        client.virtual_hid_keyboard_ready.connect([&](bool ready) { driverState(ready); });
        client.closed.connect([&] { driverState(false); });
        client.connect_failed.connect([&](auto error) {
            driverState(false);os_log_error(log,"Virtual HID connection failed: %{public}d",error.value());
        });
        client.error_occurred.connect([&](auto error) {
            driverState(false);os_log_error(log,"Virtual HID error: %{public}d",error.value());
        });
        client.async_start();
        HIDReports reports;
        uint64_t active_generation=0;
        while(running.load()) {
            (void)wake.try_acquire_for(std::chrono::milliseconds(100));
            while(wake.try_acquire()) {}
            // A hung input loop must not leave a seized keyboard or a held
            // virtual modifier behind. Process exit closes both connections.
            auto heartbeat=heartbeat_ns.load();
            if(heartbeat && now()-heartbeat>2'000'000'000ULL) {
                os_log_fault(log,"Input loop stalled; terminating to release keyboards");
                _Exit(75);
            }
            const auto wanted=generation.load();
            if(wanted!=active_generation) {
                if(driver_ready.load())reports.reset(client);
                else reports.clear();
                active_generation=wanted;
                accepting.store(driver_ready.load() && generation.load()==active_generation);
            }
            OutputEvent event;
            while(queue.pop(event)) {
                if(event.generation==active_generation && ready() && generation.load()==active_generation)
                    reports.apply(event.key,event.down,client);
            }
        }
        accepting.store(false);
        if(driver_ready.load())reports.reset(client);
        // client destruction closes the daemon connection, which destroys its
        // virtual device even if an async reset has not been delivered yet.
    }
public:
    explicit VirtualHIDOutput(const char* subsystem):log(os_log_create(subsystem,"virtual-hid")) {
        pqrs::dispatcher::extra::initialize_shared_dispatcher();
        worker=std::thread([this] { run(); });
    }
    ~VirtualHIDOutput() {
        running.store(false);wake.release();worker.join();
        pqrs::dispatcher::extra::terminate_shared_dispatcher();
    }
    bool ready() const { return accepting.load() && driver_ready.load(); }
    uint64_t epoch() const { return generation.load(); }
    void heartbeat() { heartbeat_ns.store(now()); }
    void reset() { accepting.store(false);generation.fetch_add(1);wake.release(); }
    bool send(Key key,bool down) {
        const auto session=generation.load();
        if(!ready())return false;
        if(!queue.push({key,down,session})) { reset();return false; }
        wake.release();return true;
    }
};
}
