#include "Transport.hpp"
#include "Keys.hpp"
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <poll.h>
#include <signal.h>
#include <iostream>
#include <sys/file.h>
#include <os/log.h>
namespace service=pqrs::karabiner::driverkit::virtual_hid_device_service;
namespace report=pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;
volatile sig_atomic_t running=1;
int main(){
    if(geteuid()!=0){std::cerr<<"rekey-vhid must run as root\n";return 77;}
    umask(0077);mkdir("/var/run/rekey",0700);
    int lock=open("/var/run/rekey/vhid.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lock<0||flock(lock,LOCK_EX|LOCK_NB)!=0)return 73;
    signal(SIGTERM,[](int){running=0;});signal(SIGINT,[](int){running=0;});
    shm_unlink(rekey::memory_name);auto ring=rekey::map_ring(true);if(!ring)return 74;
    int server=socket(AF_UNIX,SOCK_STREAM,0);sockaddr_un addr{};addr.sun_family=AF_UNIX;strlcpy(addr.sun_path,rekey::socket_path,sizeof(addr.sun_path));unlink(addr.sun_path);
    if(server<0||bind(server,(sockaddr*)&addr,sizeof(addr))||chmod(addr.sun_path,0600)||listen(server,1))return 74;
    pqrs::dispatcher::extra::initialize_shared_dispatcher();
    {
        service::client client;
        auto log=os_log_create("jp.example.rekey","virtual-hid");
        client.connected.connect([&]{os_log_info(log,"Evaluation driver service connected");service::virtual_hid_keyboard_parameters p;p.set_country_code(pqrs::hid::country_code::us);client.async_virtual_hid_keyboard_initialize(p);});
        client.virtual_hid_keyboard_ready.connect([&](bool ready){ring->ready.store(ready,std::memory_order_release);os_log_info(log,"Virtual keyboard ready: %{public}d",ready);});
        client.connect_failed.connect([&](auto error){os_log_error(log,"Evaluation driver connection failed: %{public}d",error.value());});
        client.error_occurred.connect([&](auto error){os_log_error(log,"Evaluation driver service error: %{public}d",error.value());});
        client.warning_reported.connect([&](auto warning){os_log_error(log,"Evaluation driver warning: %{public}s",warning.c_str());});
        client.closed.connect([&]{ring->ready.store(false,std::memory_order_release);os_log_info(log,"Evaluation driver service disconnected");});
        client.async_start();
        report::keyboard_input keyboard;report::consumer_input consumer;report::apple_vendor_keyboard_input apple_keyboard;report::apple_vendor_top_case_input top_case;std::array<uint16_t,rekey::max_keys> counts{};
        auto reset=[&]{counts={};keyboard=report::keyboard_input();consumer=report::consumer_input();apple_keyboard=report::apple_vendor_keyboard_input();top_case=report::apple_vendor_top_case_input();client.async_post_report(keyboard);client.async_post_report(consumer);client.async_post_report(apple_keyboard);client.async_post_report(top_case);};
        int peer=-1;bool was_ready=false;
        while(running){
            pollfd fds[2]={{server,POLLIN,0},{peer,POLLIN,0}};int n=poll(fds,2,100);if(n<0&&errno!=EINTR)break;
            if(fds[0].revents&POLLIN){int fd=accept(server,nullptr,nullptr);uid_t uid;gid_t gid;if(fd<0)continue;if(peer>=0||getpeereid(fd,&uid,&gid)||uid!=0){close(fd);continue;}peer=fd;reset();ring->read.store(ring->write.load(std::memory_order_acquire),std::memory_order_release);int yes=1;setsockopt(peer,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));char ack='R';if(send(peer,&ack,1,0)!=1){close(peer);peer=-1;}}
            if(peer>=0 && (fds[1].revents&(POLLIN|POLLHUP|POLLERR))){char bytes[256];auto r=recv(peer,bytes,sizeof(bytes),MSG_DONTWAIT);if(r==0||(r<0&&errno!=EAGAIN&&errno!=EINTR)){close(peer);peer=-1;reset();ring->read.store(ring->write.load(std::memory_order_acquire),std::memory_order_release);}}
            bool ready=ring->ready.load(std::memory_order_acquire);if(ready!=was_ready){reset();was_ready=ready;}
            if(peer<0)continue;
            rekey::WireEvent e;
            while(ring->pop(e)){
                if(!ring->ready.load(std::memory_order_acquire))continue;
                auto index=rekey::slot(e.key);if(index>=counts.size())continue;
                auto& count=counts[index];bool change=false;
                if(e.down){if(count<65535)change=(count++==0);}else if(count)change=(--count==0);
                if(!change)continue;
                if(e.key>=224&&e.key<=231){auto mod=static_cast<report::modifier>(1<<(e.key-224));if(e.down)keyboard.modifiers.insert(mod);else keyboard.modifiers.erase(mod);client.async_post_report(keyboard);}
                else if(e.key<256){if(e.down)keyboard.keys.insert(e.key);else keyboard.keys.erase(e.key);client.async_post_report(keyboard);}
                else if((e.key>>16)==0xff01){if(e.down)apple_keyboard.keys.insert(e.key&65535);else apple_keyboard.keys.erase(e.key&65535);client.async_post_report(apple_keyboard);}
                else if((e.key>>16)==0xff){if(e.down)top_case.keys.insert(e.key&65535);else top_case.keys.erase(e.key&65535);client.async_post_report(top_case);}
                else if((e.key>>16)==12){if(e.down)consumer.keys.insert(e.key&65535);else consumer.keys.erase(e.key&65535);client.async_post_report(consumer);}
            }
        }
        ring->ready.store(false,std::memory_order_release);reset();if(peer>=0)close(peer);
    }
    pqrs::dispatcher::extra::terminate_shared_dispatcher();close(server);unlink(rekey::socket_path);munmap(ring,sizeof(rekey::Ring));shm_unlink(rekey::memory_name);close(lock);return 0;
}
