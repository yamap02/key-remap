#pragma once
#include <cstdint>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <os/log.h>
#include <pthread.h>

namespace rekey {
// Event-path threads wake briefly for each key. The scheduler demotes a
// real-time thread that keeps overrunning its budget, so occasional long work
// on these threads (config parsing on the main loop) degrades to normal priority.
inline void make_realtime(const char* name) {
    mach_timebase_info_data_t base{};mach_timebase_info(&base);
    auto ticks=[&](uint64_t ns){return uint32_t(ns*base.denom/base.numer);};
    thread_time_constraint_policy_data_t policy{0,ticks(1'000'000),ticks(2'000'000),true};
    auto result=thread_policy_set(pthread_mach_thread_np(pthread_self()),THREAD_TIME_CONSTRAINT_POLICY,
        reinterpret_cast<thread_policy_t>(&policy),THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    if(result!=KERN_SUCCESS)os_log_error(OS_LOG_DEFAULT,"ReKey %{public}s thread priority unchanged: %{public}d",name,result);
}
}
