#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdexcept>
#include <cstring>
namespace rekey {
constexpr const char* socket_path="/var/run/rekey/vhid.sock";
constexpr const char* memory_name="/jp.example.rekey.events.v1";
constexpr size_t ring_capacity=4096;
struct WireEvent { uint32_t key=0;uint32_t down=0;uint64_t nanoseconds=0; };
struct Ring {
    uint64_t magic=0x52454b4559303031ULL;
    alignas(64) std::atomic<uint64_t> write{0};
    alignas(64) std::atomic<uint64_t> read{0};
    alignas(64) std::atomic<bool> ready{false};
    std::array<WireEvent,ring_capacity> events{};
    bool push(WireEvent e){auto w=write.load(std::memory_order_relaxed);if(w-read.load(std::memory_order_acquire)>=ring_capacity)return false;events[w%ring_capacity]=e;write.store(w+1,std::memory_order_release);return true;}
    bool pop(WireEvent& e){auto r=read.load(std::memory_order_relaxed);if(r==write.load(std::memory_order_acquire))return false;e=events[r%ring_capacity];read.store(r+1,std::memory_order_release);return true;}
};
static_assert(std::atomic<uint64_t>::is_always_lock_free);
inline int connect_vhid() {
    int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return -1;sockaddr_un address{};address.sun_family=AF_UNIX;strlcpy(address.sun_path,socket_path,sizeof(address.sun_path));
    if(connect(fd,(sockaddr*)&address,sizeof(address))!=0){close(fd);return -1;}
    uid_t uid;gid_t gid;if(getpeereid(fd,&uid,&gid)!=0||uid!=0){close(fd);return -1;}
    int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    timeval timeout{1,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    char ready=0;if(recv(fd,&ready,1,0)!=1||ready!='R'){close(fd);return -1;}
    return fd;
}
inline size_t ring_storage_size() {
    const auto page=size_t(getpagesize());
    return ((sizeof(Ring)+page-1)/page)*page;
}
// The alternative name/owner support isolated, unprivileged transport tests.
// Both production callers use the fixed root-owned name and owner below.
inline Ring* map_ring(bool create,const char* name=memory_name,uid_t owner=0) {
    int fd=shm_open(name,create?(O_CREAT|O_EXCL|O_RDWR):O_RDWR,0600);if(fd<0)return nullptr;
    struct stat st{};if(fstat(fd,&st)!=0||st.st_uid!=owner||(st.st_mode&077)!=0){close(fd);return nullptr;}
    const auto storage_size=ring_storage_size();
    if(create&&ftruncate(fd,storage_size)!=0){close(fd);shm_unlink(name);return nullptr;}
    if(!create&&st.st_size!=off_t(storage_size)){close(fd);return nullptr;}
    auto ptr=mmap(nullptr,sizeof(Ring),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);close(fd);if(ptr==MAP_FAILED)return nullptr;
    auto ring=static_cast<Ring*>(ptr);if(create)new(ring)Ring();else if(ring->magic!=0x52454b4559303031ULL){munmap(ptr,sizeof(Ring));return nullptr;}return ring;
}
}
