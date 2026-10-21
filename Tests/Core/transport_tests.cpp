#include "Transport.hpp"
#include <thread>
#include <iostream>
#include <cstdlib>
int main(){
    const auto name="/rekey-transport-test-"+std::to_string(getpid());
    auto writer=rekey::map_ring(true,name.c_str(),getuid());
    if(!writer)return 5;
    auto reader=rekey::map_ring(false,name.c_str(),getuid());
    if(!reader)return 6;
    if(!writer->push({42,1,1234}))return 7;
    rekey::WireEvent shared;
    if(!reader->pop(shared)||shared.key!=42||shared.nanoseconds!=1234)return 8;
    writer->ready.store(true);
    if(!reader->ready.load())return 9;
    if(getuid()!=0&&rekey::map_ring(false,name.c_str())!=nullptr)return 10;
    munmap(writer,sizeof(rekey::Ring));munmap(reader,sizeof(rekey::Ring));shm_unlink(name.c_str());
    auto ring=std::make_unique<rekey::Ring>();
    for(size_t i=0;i<rekey::ring_capacity;++i)if(!ring->push({uint32_t(i),1,i}))return 1;
    if(ring->push({}))return 2;
    for(size_t i=0;i<rekey::ring_capacity;++i){rekey::WireEvent e;if(!ring->pop(e)||e.key!=i||e.nanoseconds!=i)return 3;}
    rekey::WireEvent e;if(ring->pop(e))return 4;
    constexpr uint32_t count=100000;
    std::thread producer([&]{for(uint32_t i=0;i<count;++i){while(!ring->push({i,i%2,i}))std::this_thread::yield();}});
    for(uint32_t i=0;i<count;++i){while(!ring->pop(e))std::this_thread::yield();if(e.key!=i||e.down!=i%2||e.nanoseconds!=i)std::abort();}
    producer.join();std::cout<<"PASS POSIX shared memory mapping, ownership, ring capacity, overflow, empty and 100000 ordered concurrent events\n";
}
