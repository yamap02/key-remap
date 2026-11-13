#include "VirtualHIDOutput.hpp"
#include <sys/wait.h>
#include <unistd.h>
#include <iostream>
#include <stdexcept>

int main() {
    // Production's root-only daemon must remain inaccessible to this test.
    if(geteuid()==0){std::cerr<<"Run output lifecycle tests as a normal user\n";return 77;}
    {
        rekey::VirtualHIDOutput output("jp.example.rekey.tests");
        const auto initial=output.epoch();
        for(int i=0;i<10;++i){output.heartbeat();std::this_thread::sleep_for(std::chrono::milliseconds(25));}
        if(output.ready() || output.epoch()!=initial){std::cerr<<"Offline output changed sessions or became ready\n";return 1;}
        output.reset();
        for(int i=0;i<10;++i){output.heartbeat();std::this_thread::sleep_for(std::chrono::milliseconds(25));}
        if(output.ready() || output.epoch()!=initial+1){std::cerr<<"Offline reset caused a feedback loop\n";return 2;}
    }
    // The output worker independently detects a stalled capture/main thread.
    auto child=fork();
    if(child<0)return 3;
    if(child==0){
        rekey::VirtualHIDOutput output("jp.example.rekey.tests");
        output.heartbeat();
        std::this_thread::sleep_for(std::chrono::seconds(4));
        _Exit(9);
    }
    int status=0;
    if(waitpid(child,&status,0)!=child || !WIFEXITED(status) || WEXITSTATUS(status)!=75)return 4;
    std::cout<<"PASS offline connection/reset without feedback, graceful worker shutdown and main-loop stall watchdog\n";
}
