#import "Control.h"
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include "Engine.hpp"
#include "VirtualHIDOutput.hpp"
#include "PowerState.hpp"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <pwd.h>
#include <fstream>
#include <iostream>
#include <libproc.h>
#include <sys/file.h>
#include <signal.h>
#include <os/log.h>
#include <mach/mach_time.h>
#include <mach-o/dyld.h>

namespace {
uint64_t now_ms(){return uint64_t(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)/1000000);}
struct Device { IOHIDDeviceRef hid=nullptr;rekey::Identity identity;std::string name;std::unique_ptr<rekey::Engine> engine;bool seized=false,muted=false;uint64_t inputs=0,outputs=0,started=0,retry_at=0,capture_started=0; };
struct Trace {uint64_t time;uint32_t device,key,output;bool down,output_down;int rule;uint8_t input_modifiers,output_modifiers;};
class Core {
public:
    rekey::PowerState power;
    IONotificationPortRef system_port=nullptr,display_port=nullptr;
    io_connect_t power_connection=IO_OBJECT_NULL;
    io_object_t system_notifier=IO_OBJECT_NULL,display_notifier=IO_OBJECT_NULL;
    IOHIDManagerRef manager=nullptr;std::array<Device,32> devices{};rekey::JSON config;std::string error="Configuration not loaded";uid_t uid=0;std::string config_path;time_t modified=0;long modified_ns=0;dispatch_source_t config_watch=nullptr,link_watch=nullptr;std::string watch_path;
    rekey::VirtualHIDOutput output;uint64_t output_epoch=0;bool paused=true,viewer=false,secure=true,conflict=false,input_monitoring=false,agent_accessibility=false;uint64_t viewer_deadline=0,housekeeping=0,last_context=0,ui_deadline=0;std::array<Trace,2048> traces{};size_t trace_write=0,trace_read=0;struct PendingAction {uint32_t device;int action;};std::array<PendingAction,256> actions{};size_t action_write=0,action_read=0;rekey::Context context;
    Core(){
        manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDManagerOptionIndependentDevices);NSDictionary* match=@{@kIOHIDDeviceUsagePageKey:@1,@kIOHIDDeviceUsageKey:@6};IOHIDManagerSetDeviceMatching(manager,(__bridge CFDictionaryRef)match);
        IOHIDManagerRegisterDeviceMatchingCallback(manager,[](void* ctx,IOReturn,void*,IOHIDDeviceRef d){static_cast<Core*>(ctx)->add(d);},this);
        IOHIDManagerRegisterDeviceRemovalCallback(manager,[](void* ctx,IOReturn,void*,IOHIDDeviceRef d){static_cast<Core*>(ctx)->remove(d);},this);
        IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopDefaultMode);IOHIDManagerOpen(manager,0);
        power_connection=IORegisterForSystemPower(this,&system_port,[](void* ctx,io_service_t,natural_t message,void* argument){
            auto& c=*static_cast<Core*>(ctx);
            if(message==kIOMessageSystemWillSleep)c.power_changed(c.power.system(true));
            else if(message==kIOMessageSystemHasPoweredOn)c.power_changed(c.power.system(false));
            if(message==kIOMessageCanSystemSleep||message==kIOMessageSystemWillSleep)
                IOAllowPowerChange(c.power_connection,reinterpret_cast<intptr_t>(argument));
        },&system_notifier);
        if(system_port)CFRunLoopAddSource(CFRunLoopGetMain(),IONotificationPortGetRunLoopSource(system_port),kCFRunLoopDefaultMode);
        display_port=IONotificationPortCreate(kIOMainPortDefault);
        auto display=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IODisplayWrangler"));
        if(display&&display_port){
            IOServiceAddInterestNotification(display_port,display,kIOGeneralInterest,[](void* ctx,io_service_t,natural_t message,void*){
                auto& c=*static_cast<Core*>(ctx);
                if(message==kIOMessageDeviceWillPowerOff)c.power_changed(c.power.display(true));
                else if(message==kIOMessageDeviceHasPoweredOn)c.power_changed(c.power.display(false));
            },this,&display_notifier);
        }
        if(display)IOObjectRelease(display);
        if(display_port)CFRunLoopAddSource(CFRunLoopGetMain(),IONotificationPortGetRunLoopSource(display_port),kCFRunLoopDefaultMode);
        if(!power_connection||!display_notifier)os_log_error(OS_LOG_DEFAULT,"ReKey power notifications unavailable: system=%{public}d display=%{public}d",bool(power_connection),bool(display_notifier));
    }
    ~Core(){if(system_notifier)IODeregisterForSystemPower(&system_notifier);if(power_connection)IOServiceClose(power_connection);if(display_notifier)IOObjectRelease(display_notifier);if(system_port)IONotificationPortDestroy(system_port);if(display_port)IONotificationPortDestroy(display_port);if(config_watch)dispatch_source_cancel(config_watch);if(link_watch)dispatch_source_cancel(link_watch);stop();IOHIDManagerClose(manager,0);CFRelease(manager);}
    void power_changed(bool changed){
        if(!changed)return;
        stop();
        // Invalidate queued downs as well as the engine's held keys. The worker
        // sends empty reports for every HID report family on this new epoch.
        output.reset();
        for(auto& d:devices){if(d.engine)(void)d.engine->release_all(now_ms());d.retry_at=0;}
        os_log_info(OS_LOG_DEFAULT,"ReKey power transition; capture suspended=%{public}d",power.suspended());
    }
    void add(IOHIDDeviceRef hid){
        auto str=[&](CFStringRef k){auto v=IOHIDDeviceGetProperty(hid,k);return v&&CFGetTypeID(v)==CFStringGetTypeID()?std::string([(__bridge NSString*)v UTF8String]):std::string();};
        auto num=[&](CFStringRef k){int n=0;auto v=IOHIDDeviceGetProperty(hid,k);if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)v,kCFNumberIntType,&n);return n;};
        auto name=str(CFSTR(kIOHIDProductKey));if(name.find("VirtualHID")!=std::string::npos||name.find("ReKey Virtual")!=std::string::npos)return;
        for(auto& d:devices)if(d.hid==hid)return;
        for(auto& d:devices)if(!d.hid){d.hid=hid;d.name=name;CFRetain(hid);d.identity={num(CFSTR(kIOHIDVendorIDKey)),num(CFSTR(kIOHIDProductIDKey)),str(CFSTR(kIOHIDSerialNumberKey)),false,"unknown"};int keyboard_type=num(CFSTR("KeyboardType"));int country=num(CFSTR(kIOHIDCountryCodeKey));d.identity.keyboard_type=keyboard_type==42||country==15?"jis":keyboard_type==41||country==32?"iso":keyboard_type==40||country==33?"ansi":"unknown";auto built=IOHIDDeviceGetProperty(hid,CFSTR(kIOHIDBuiltInKey));d.identity.builtin=built==kCFBooleanTrue||num(CFSTR(kIOHIDBuiltInKey))!=0;compile(d);break;}
    }
    void remove(IOHIDDeviceRef hid){trace_read=trace_write;action_read=action_write;for(auto& d:devices)if(d.hid==hid){release(d);CFRelease(d.hid);d=Device();break;}}
    void compile(Device& d){if(config.is_null())return;try{auto e=std::make_unique<rekey::Engine>(rekey::Program::compile(config,d.identity),d.identity);e->update_context(context);release(d);d.engine=std::move(e);}catch(const std::exception& e){error=e.what();paused=true;stop();}}
    void stop(){action_read=action_write;bool seized=false;for(auto& d:devices){seized=seized||d.seized;release(d);}if(seized)output.reset();viewer=false;trace_read=trace_write;}
    void release(Device& d){if(d.seized){if(d.engine)send(d.engine->release_all(now_ms()),d);IOHIDDeviceUnscheduleFromRunLoop(d.hid,CFRunLoopGetMain(),kCFRunLoopDefaultMode);IOHIDDeviceClose(d.hid,0);d.seized=false;}}
    void send(const rekey::Outputs& out,Device& d){
        if(!output.ready())return;
        for(size_t i=0;i<out.user_action_count;++i){if(action_write-action_read==actions.size()){paused=true;output.reset();error="User action queue overflow";return;}actions[action_write++%actions.size()]={uint32_t(&d-devices.data()),out.user_actions[i]};}
        if(out.overflow){output.reset();paused=true;error="Output batch overflow; remapping paused";return;}
        for(size_t i=0;i<out.size;++i){auto& e=out.values[i];if(!output.send(e.key,e.down)){output.reset();paused=true;error="Virtual HID output unavailable or queue overflow; remapping paused";break;}++d.outputs;}
    }

    void value(IOHIDValueRef v){
        if(power.suspended())return;
        if(output_epoch!=output.epoch()||!output.ready()){stop();return;}
        auto element=IOHIDValueGetElement(v);auto hid=IOHIDElementGetDevice(element);auto page=IOHIDElementGetUsagePage(element),usage=IOHIDElementGetUsage(element);if((page!=7&&page!=12&&page!=0xff&&page!=0xff01)||usage==0)return;
        Device* d=nullptr;for(auto& x:devices)if(x.hid==hid){d=&x;break;}if(!d||!d->seized||!d->engine||d->muted)return;
        if(IOHIDValueGetTimeStamp(v)<d->capture_started)return;
        rekey::Key key=page==7?usage:(page<<16)|usage;bool down=IOHIDValueGetIntegerValue(v)!=0;if(d->inputs++==0)d->started=now_ms();
        auto out=d->engine->process({key,down,now_ms(),uint32_t(d-devices.data())});if(!d->muted)send(out,*d);
        record(key,down,out,*d);
    }
    void record(rekey::Key input,bool down,const rekey::Outputs& out,Device& d){
        if(viewer&&!secure&&now_ms()-last_context<500&&!IsSecureEventInputEnabled()){
            size_t count=std::max(size_t(1),out.size);for(size_t i=0;i<count;++i){if(trace_write-trace_read>=traces.size())++trace_read;
                traces[trace_write++%traces.size()]={clock_gettime_nsec_np(CLOCK_UPTIME_RAW),uint32_t(&d-devices.data()),input,i<out.size?out.values[i].key:0,down,i<out.size?out.values[i].down:false,i<out.size?out.values[i].rule:-1,d.engine->input_modifiers(),d.engine->output_modifiers()};
            }
        }
    }

    bool karabiner(){
        int bytes=proc_listallpids(nullptr,0);std::vector<pid_t> pids(size_t(bytes)+32);
        int count=proc_listallpids(pids.data(),int(pids.size()*sizeof(pid_t)));
        for(int i=0;i<count;++i){char path[PROC_PIDPATHINFO_MAXSIZE]{};if(proc_pidpath(pids[i],path,sizeof(path))>0){std::string name=path;if(name.ends_with("/Karabiner-Core-Service")||name.ends_with("/karabiner_grabber"))return true;}}
        return false;
    }
    dispatch_source_t watch_directory(const std::string& path){
        int fd=open(path.c_str(),O_EVTONLY|O_CLOEXEC);if(fd<0)return nullptr;
        auto source=dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,uintptr_t(fd),DISPATCH_VNODE_WRITE|DISPATCH_VNODE_DELETE|DISPATCH_VNODE_RENAME,dispatch_get_main_queue());
        dispatch_source_set_event_handler(source,^{core_load();});dispatch_source_set_cancel_handler(source,^{close(fd);});dispatch_resume(source);return source;
    }
    void core_load(){load();}
    void load(){
        uid_t console_uid=0;gid_t gid=0;CFStringRef user=SCDynamicStoreCopyConsoleUser(nullptr,&console_uid,&gid);if(user)CFRelease(user);
        if(console_uid<501){paused=true;uid=0;stop();return;}
        auto pw=getpwuid(console_uid);if(!pw)return;std::string path=std::string(pw->pw_dir)+"/Library/Application Support/ReKey/rekey.json";
        struct stat st{};if(stat(path.c_str(),&st)!=0){paused=true;error="Configuration file not found";stop();return;}
        if(st.st_uid!=console_uid||(st.st_mode&077)!=0||!S_ISREG(st.st_mode)||st.st_size>4*1024*1024){paused=true;error="Configuration ownership, permissions or size rejected";stop();return;}
        if(uid==console_uid&&st.st_mtimespec.tv_sec==modified&&st.st_mtimespec.tv_nsec==modified_ns)return;
        try {
            int fd=open(path.c_str(),O_RDONLY|O_CLOEXEC);if(fd<0)throw std::runtime_error("Configuration open failed");struct stat opened{};if(fstat(fd,&opened)||opened.st_uid!=console_uid||opened.st_ino!=st.st_ino){close(fd);throw std::runtime_error("Configuration changed during open");}
            std::string data(size_t(opened.st_size),'\0');auto read_count=read(fd,data.data(),data.size());close(fd);if(read_count!=ssize_t(data.size()))throw std::runtime_error("Configuration read failed");
            auto candidate=rekey::JSON::parse(data);
            // Validate all device programs before replacing the active configuration.
            auto trial=rekey::Program::compile(candidate,{});for(auto& d:devices)if(d.hid)(void)rekey::Program::compile(candidate,d.identity);
            stop();
            char resolved[PATH_MAX]{};if(realpath(path.c_str(),resolved)){std::string actual=resolved;actual=actual.substr(0,actual.find_last_of('/'));if(watch_path!=actual){if(config_watch)dispatch_source_cancel(config_watch);if(link_watch)dispatch_source_cancel(link_watch);config_watch=watch_directory(actual);auto original=path.substr(0,path.find_last_of('/'));link_watch=original!=actual?watch_directory(original):nullptr;watch_path=actual;}}
            config=std::move(candidate);uid=console_uid;config_path=path;modified=st.st_mtimespec.tv_sec;modified_ns=st.st_mtimespec.tv_nsec;paused=config.at("global").value("paused",false);error="";for(auto& d:devices)if(d.hid)compile(d);
        }catch(const std::exception& e){error=e.what(); /* Keep the last valid program and settings. */}
    }
    void tick(){
        if(now_ms()-housekeeping>=1000){housekeeping=now_ms();load();conflict=karabiner();input_monitoring=IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted;}
        output.heartbeat();
        if(output_epoch!=output.epoch()){stop();output_epoch=output.epoch();}
        if(power.suspended()||paused||(config.is_object()&&config.at("global").value("disable_on_quit",true)&&now_ms()>ui_deadline)||conflict||!output.ready()){stop();return;}
        if(!input_monitoring){error="Input Monitoring permission is required for rekey-core";stop();return;}
        bool disable_builtin=false;for(auto& d:devices)if(d.hid&&!d.identity.builtin&&d.engine&&d.engine->program().disable_builtin)disable_builtin=true;
        for(auto& d:devices){if(!d.hid||!d.engine)continue;if(d.engine->program().ignore){release(d);continue;}
            if(!d.seized){if(now_ms()<d.retry_at)continue;d.capture_started=mach_absolute_time();auto result=IOHIDDeviceOpen(d.hid,kIOHIDOptionsTypeSeizeDevice);if(result!=kIOReturnSuccess){d.retry_at=now_ms()+1000;error="Keyboard could not be seized (Input Monitoring or another remapper)";continue;}d.retry_at=0;if(error=="Keyboard could not be seized (Input Monitoring or another remapper)"||error=="Input Monitoring permission is required for rekey-core")error.clear();d.seized=true;d.inputs=0;d.outputs=0;d.started=now_ms();IOHIDDeviceRegisterInputValueCallback(d.hid,[](void* ctx,IOReturn,void*,IOHIDValueRef v){static_cast<Core*>(ctx)->value(v);},this);IOHIDDeviceScheduleWithRunLoop(d.hid,CFRunLoopGetMain(),kCFRunLoopDefaultMode);}
            if(d.engine->paused()){paused=true;error="Emergency stop activated";break;}
            bool mute=disable_builtin&&d.identity.builtin;if(mute&&!d.muted)send(d.engine->release_all(now_ms()),d);d.muted=mute;
            if(d.muted)continue;
            auto timed=d.engine->tick(now_ms());send(timed,d);if(timed.size)record(0,false,timed,d);
            if(d.inputs&&d.outputs==0&&now_ms()-d.started>10000){paused=true;error="Failsafe: no output for ten seconds";break;}
        }
        if(paused)stop();
        if(viewer&&now_ms()>viewer_deadline){viewer=false;trace_read=trace_write;}
    }
    NSString* status(){size_t seized=0;for(auto& d:devices)if(d.seized)++seized;rekey::JSON j={{"paused",paused},{"driver_ready",output.ready()},{"input_monitoring",input_monitoring},{"agent_accessibility",agent_accessibility&&now_ms()-last_context<500},{"seized_devices",seized},{"conflict",conflict},{"error",error},{"uid",uid}};return [NSString stringWithUTF8String:j.dump().c_str()];}
    NSData* take_actions(){rekey::JSON a=rekey::JSON::array();while(action_read<action_write){auto request=actions[action_read++%actions.size()];auto& d=devices[request.device];if(d.engine&&request.action>=0&&size_t(request.action)<d.engine->program().user_actions.size())a.push_back(d.engine->program().user_actions[request.action]);}auto s=a.dump();return [NSData dataWithBytes:s.data() length:s.size()];}
    NSData* events(bool enabled){
        viewer=enabled;viewer_deadline=now_ms()+4000;rekey::JSON a=rekey::JSON::array();
        if(!enabled||secure||now_ms()-last_context>=500||IsSecureEventInputEnabled()){trace_read=trace_write;}
        else while(trace_read<trace_write){auto e=traces[trace_read++%traces.size()];auto& d=devices[e.device];std::string rule;if(d.engine&&e.rule>=0&&size_t(e.rule)<d.engine->program().rules.size())rule=d.engine->program().rules[e.rule].name;
            a.push_back({{"time_ns",e.time},{"device",e.device},{"device_name",d.name},{"vendor_id",d.identity.vendor},{"product_id",d.identity.product},{"input",e.key},{"input_down",e.down},{"output",e.output},{"output_down",e.output_down},{"rule",e.rule},{"input_modifiers",e.input_modifiers},{"output_modifiers",e.output_modifiers},{"rule_name",rule.empty()?rekey::JSON(nullptr):rekey::JSON(rule)}});
        }auto s=a.dump();return [NSData dataWithBytes:s.data() length:s.size()];
    }

};// Core
Core* core=nullptr;
}

namespace {
bool allowed(uid_t caller,bool require_owner){uid_t console=0;gid_t gid;CFStringRef user=SCDynamicStoreCopyConsoleUser(nullptr,&console,&gid);if(user)CFRelease(user);return caller>=501&&caller==console&&(!require_owner||caller==core->uid);}
}
@interface Control : NSObject <ReKeyControl>
@end
@implementation Control
- (void)requestInputMonitoringWithReply:(void (^)(BOOL))reply {
    uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!allowed(caller,false)){reply(NO);return;}
        // Request from the process that opens keyboards, never from the settings UI.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
        core->input_monitoring=IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted;
        reply(core->input_monitoring);
    });
}
- (void)lifecycleWithActive:(BOOL)active reply:(void (^)(BOOL))reply {
    uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{if(!allowed(caller,false)){reply(NO);return;}core->ui_deadline=active?now_ms()+5000:0;if(!active&&core->config.is_object()&&core->config.at("global").value("disable_on_quit",true))core->stop();reply(YES);});
}
- (void)reloadWithReply:(void (^)(BOOL))reply {
    uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{if(!allowed(caller,true)){reply(NO);return;}core->modified=0;core->modified_ns=0;core->load();reply(core->error.empty());});
}
- (void)statusWithReply:(void (^)(NSString *))reply {
    uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{if(allowed(caller,false)){core->ui_deadline=now_ms()+5000;reply(core->status());}else reply(@"{}");});
}
- (void)contextWithApp:(NSString*)app inputSource:(NSString*)source secure:(BOOL)secure accessibility:(BOOL)accessibility reply:(void (^)(BOOL))reply {
    if(app.length>512||source.length>512){reply(NO);return;}uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{if(!allowed(caller,true)){reply(NO);return;}bool context_changed=core->context.app!=app.UTF8String||core->context.input_source!=source.UTF8String;core->context={app.UTF8String,source.UTF8String};core->agent_accessibility=accessibility;core->secure=secure||!accessibility;core->last_context=now_ms();if(core->secure)core->trace_read=core->trace_write;if(context_changed)for(auto& d:core->devices)if(d.engine)d.engine->update_context(core->context);reply(YES);});
}
- (void)viewerRequestedWithReply:(void (^)(BOOL))reply {
    uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{reply(allowed(caller,true)&&core->viewer&&now_ms()<core->viewer_deadline);});
}
- (void)actionsWithReply:(void (^)(NSData*))reply {uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;dispatch_async(dispatch_get_main_queue(), ^{reply(allowed(caller,true)?core->take_actions():[NSData data]);});}
- (void)eventsWithEnabled:(BOOL)enabled reply:(void (^)(NSData*))reply {uid_t caller=[NSXPCConnection currentConnection].effectiveUserIdentifier;dispatch_async(dispatch_get_main_queue(), ^{reply(allowed(caller,true)?core->events(enabled):[NSData data]);});}
@end
@interface Listener : NSObject <NSXPCListenerDelegate>
@property(nonatomic,copy) NSString* requirement;
@end
@implementation Listener
- (BOOL)listener:(NSXPCListener*)listener shouldAcceptNewConnection:(NSXPCConnection*)connection {
    (void)listener;
    uid_t uid=connection.effectiveUserIdentifier;uid_t console=0;gid_t gid;CFStringRef u=SCDynamicStoreCopyConsoleUser(nullptr,&console,&gid);if(u)CFRelease(u);
    if(uid<501||uid!=console||!self.requirement.length)return NO;
    [connection setCodeSigningRequirement:self.requirement];connection.exportedInterface=[NSXPCInterface interfaceWithProtocol:@protocol(ReKeyControl)];connection.exportedObject=[Control new];[connection resume];return YES;
}
@end
int main(int argc,const char* argv[]){
    @autoreleasepool {
        if(argc==3 && std::string(argv[1])=="--validate"){try{std::ifstream f(argv[2]);auto j=rekey::JSON::parse(f);auto p=rekey::Program::compile(j,{});for(auto& profile:j.at("profiles"))for(auto& d:profile.value("devices",rekey::JSON::array())){auto id=d.at("id");auto copy=j;for(auto& pp:copy["profiles"])pp["selected"]=(pp.at("id")==profile.at("id"));(void)rekey::Program::compile(copy,{id.at("vendor_id"),id.at("product_id"),id.value("serial",std::string())});}std::cout<<"Valid: "<<p.rules.size()<<" manipulators\n";return 0;}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 65;}}
        if(geteuid()!=0){std::cerr<<"rekey-core must run as root; use --validate FILE for offline validation\n";return 77;}
        umask(0077);mkdir("/var/run/rekey",0700);int lock=open("/var/run/rekey/core.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0600);if(lock<0||flock(lock,LOCK_EX|LOCK_NB))return 73;
        Core instance;core=&instance;
        // Pin clients to the installed app and Agent designated requirements. The installer owns both.
        char executable_path[PATH_MAX]{};uint32_t path_size=sizeof(executable_path);if(_NSGetExecutablePath(executable_path,&path_size)!=0)return 78;NSString* exe=[[NSString stringWithUTF8String:executable_path] stringByResolvingSymlinksInPath];
        NSString* contents=[[[exe stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSMutableArray<NSString*>* requirements=[NSMutableArray array];
        NSArray<NSString*>* paths=@[[contents stringByAppendingPathComponent:@"MacOS/ReKey"],[contents stringByAppendingPathComponent:@"Library/LoginItems/ReKeyAgent.app/Contents/MacOS/ReKeyAgent"]];
        NSArray<NSString*>* identifiers=@[@"jp.example.rekey",@"jp.example.rekey.agent"];
        for(NSUInteger i=0;i<paths.count;++i){
            NSString* path=paths[i];struct stat st{};SecStaticCodeRef code=nullptr;SecRequirementRef req=nullptr;CFStringRef requirement=nullptr;
            bool trusted=true;NSString* parent=[path stringByDeletingLastPathComponent];
            while(parent.length>=contents.length){if(stat(parent.fileSystemRepresentation,&st)||st.st_uid!=0||(st.st_mode&022)){trusted=false;break;}parent=[parent stringByDeletingLastPathComponent];}
            if(trusted&&stat(path.fileSystemRepresentation,&st)==0&&st.st_uid==0&&(st.st_mode&022)==0&&SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path],kSecCSDefaultFlags,&code)==errSecSuccess&&SecStaticCodeCheckValidity(code,kSecCSStrictValidate,nullptr)==errSecSuccess&&SecCodeCopyDesignatedRequirement(code,kSecCSDefaultFlags,&req)==errSecSuccess&&SecRequirementCopyString(req,kSecCSDefaultFlags,&requirement)==errSecSuccess){
                [requirements addObject:[NSString stringWithFormat:@"(identifier \"%@\" and (%@))",identifiers[i],(__bridge NSString*)requirement]];
            }
            if(requirement)CFRelease(requirement);if(req)CFRelease(req);if(code)CFRelease(code);
        }
        Listener* delegate=[Listener new];delegate.requirement=[requirements componentsJoinedByString:@" or "];
        NSXPCListener* listener=[[NSXPCListener alloc] initWithMachServiceName:@"jp.example.rekey.core"];listener.delegate=delegate;[listener resume];
        [NSTimer scheduledTimerWithTimeInterval:0.005 repeats:YES block:^(NSTimer*){core->tick();}];
        signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
        dispatch_source_t termination=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(termination,^{core->stop();CFRunLoopStop(CFRunLoopGetMain());});dispatch_resume(termination);
        dispatch_source_t interrupt=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(interrupt,^{core->stop();CFRunLoopStop(CFRunLoopGetMain());});dispatch_resume(interrupt);
        CFRunLoopRun();
        dispatch_source_cancel(termination);dispatch_source_cancel(interrupt);
        close(lock);
    }
}
