#include "Engine.hpp"
#include "PowerState.hpp"
#include <iostream>
#include <cstdlib>
#include <chrono>
#include <numeric>
using namespace rekey;
bool measure_allocations=false;size_t allocations=0;
void* operator new(size_t size){if(measure_allocations)++allocations;if(auto p=std::malloc(size))return p;throw std::bad_alloc();}
void operator delete(void* p) noexcept {std::free(p);}
void operator delete(void* p,size_t) noexcept {std::free(p);}
int assertions=0;
void check(bool x,const char* msg){++assertions;if(!x){std::cerr<<"FAIL: "<<msg<<'\n';std::exit(1);}}
JSON base(){return JSON::parse(R"({"schema_version":1,"global":{"thresholds_ms":{"alone":200,"held_down":500,"simultaneous":50}},"profiles":[{"name":"Default","selected":true,"simple":[],"rules":[],"layers":[],"devices":[]}]})");}
JSON rule(JSON m){return {{"name","rule"},{"manipulators",JSON::array({m})}};}
JSON basic(std::string from,std::string to){return {{"type","basic"},{"from",{{"key",from}}},{"to",JSON::array({{{"key",to}}})}};}
Engine engine(JSON c,Identity id={}){Engine e(Program::compile(c,id),id);e.update_context({});return e;}
void expect(const Outputs& out,std::initializer_list<std::pair<Key,bool>> expected,const char* msg){check(out.size==expected.size(),msg);size_t i=0;for(auto [k,d]:expected){check(out.values[i].key==k&&out.values[i].down==d,msg);++i;}}
int main(){
    {
        // Missing release across display/system sleep must not survive recovery.
        auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key","international2"}}},{"to",JSON::array({{{"key","return_or_enter"}}})}}};
        for(bool display_first:{false,true}){
            auto e=engine(c);PowerState power;
            expect(e.process({136,true,1}),{{40,true}},"wake regression Return down");
            expect(e.tick(60001),{},"ordinary long hold is preserved");
            check(display_first?power.display(true):power.system(true),"first sleep notification changes state");
            check(power.suspended(),"capture blocked before reset");
            expect(e.release_all(60002),{{40,false}},"power transition releases missing up");
            check(display_first?power.system(true):power.display(true),"second sleep source changes state");
            expect(e.release_all(60003),{},"overlapping resets have no extra output");
            check(!power.display(true)&&!power.system(true),"duplicate sleep is idempotent");
            check(display_first?power.display(false):power.system(false),"first wake changes state");
            check(power.suspended(),"one awake source cannot resume capture");
            check(display_first?power.system(false):power.display(false),"second wake changes state");
            check(!power.suspended(),"capture resumes after both wake");
            check(!power.display(false)&&!power.system(false),"duplicate wake is idempotent");
            expect(e.process({136,false,60004}),{},"late physical release cannot emit a tap");
            expect(e.process({136,true,60005}),{{40,true}},"fresh press works after wake");
            expect(e.process({136,false,60006}),{{40,false}},"fresh release works after wake");
        }
        auto e=engine(base());
        e.process({224,true,1});e.process({226,true,2});e.process({227,true,3});e.process({41,true,4});
        e.release_all(5);
        expect(e.tick(2000),{},"power reset cancels emergency hold timer");
        check(!e.paused(),"old emergency chord does not pause after wake");
        PowerState power;
        check(power.display(true)&&power.suspended(),"display-only sleep blocks capture");
        check(power.display(false)&&!power.suspended(),"display-only wake resumes capture");
    }
    {
        // Windows JIS conversion keys and Mac language keys are distinct inputs.
        const char* jis[]={"international1","international2","international3","international4","international5","japanese_kana","japanese_eisuu"};
        const Key usages[]={135,136,137,138,139,144,145};
        for(size_t i=0;i<7;++i){
            check(key(jis[i])==usages[i],"JIS physical HID usage");
            auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key",jis[i]}}},{"to",JSON::array({{{"key","return_or_enter"}}})}}};auto e=engine(c);
            expect(e.process({usages[i],true,1}),{{40,true}},"JIS remap down");
            expect(e.process({usages[i],false,2}),{{40,false}},"JIS remap up");
            c["profiles"][0]["simple"]={{{"from",{{"key","a"}}},{"to",JSON::array({{{"key",jis[i]}}})}}};e=engine(c);
            expect(e.process({4,true,1}),{{usages[i],true}},"JIS output down");
            expect(e.process({4,false,2}),{{usages[i],false}},"JIS output up");
        }
        auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key","international2"}}},{"to",JSON::array({{{"key","return_or_enter"}}})}}};auto e=engine(c);
        expect(e.process({144,true,1}),{{144,true}},"Mac kana is not Windows JIS international2");
        expect(e.process({144,false,2}),{{144,false}},"Mac kana passthrough release");
    }
    {
        auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key","a"}}},{"to",JSON::array({{{"key","b"}}})}},{{"from",{{"key","b"}}},{"to",JSON::array({{{"key","c"}}})}}};auto e=engine(c);
        expect(e.process({4,true,1}),{{5,true}},"simple down, no recursion");expect(e.process({4,false,2}),{{5,false}},"simple up");
        c["profiles"][0]["rules"]={rule(basic("b","escape"))};e=engine(c);expect(e.process({4,true,1}),{{41,true}},"simple before complex");expect(e.process({4,false,2}),{{41,false}},"complex release");
    }
    {
        auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key","a"}}},{"to",JSON::array({{{"key","b"}}})}}};c["profiles"][0]["devices"]={{{"id",{{"vendor_id",1},{"product_id",2},{"serial","A"}}},{"simple",JSON::array({{{"from",{{"key","a"}}},{"to",JSON::array({{{"key","c"}}})}}})}}};
        auto a=engine(c,{1,2,"A"}),b=engine(c,{1,2,"B"});expect(a.process({4,true,0}),{{6,true}},"device overrides global");expect(b.process({4,true,0}),{{5,true}},"serial isolation");
    }
    {
        auto c=base();auto m=basic("caps_lock","left_control");m["to_if_alone"]={{{"key","escape"}}};m["to_if_held_down"]={{{"key","left_shift"}}};m["to_after_key_up"]={{{"key","tab"}}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);
        expect(e.process({57,true,0}),{{224,true}},"tap hold immediate");expect(e.process({57,false,100}),{{224,false},{41,true},{41,false},{43,true},{43,false}},"alone and after");
        e=engine(c);e.process({57,true,100});expect(e.tick(599),{},"held not early");expect(e.tick(600),{{224,false},{225,true}},"held threshold");expect(e.process({57,false,700}),{{225,false},{43,true},{43,false}},"held release, no alone");
        e=engine(c);e.process({57,true,0});e.process({4,true,50});auto output=e.process({57,false,100});check(std::none_of(output.values.begin(),output.values.begin()+output.size,[](auto o){return o.key==41;}),"interrupted alone suppressed");
    }
    {
        auto c=base();auto m=basic("a","escape");m["from"]={{"simultaneous",JSON::array({{{"key","a"}},{{"key","b"}}})}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);
        expect(e.process({4,true,100}),{},"chord first pending");expect(e.process({5,true,120}),{{41,true}},"chord matches");expect(e.process({4,false,130}),{},"chord suppress raw release");expect(e.process({5,false,140}),{{41,false}},"chord output release");
        e=engine(c);e.process({4,true,100});expect(e.tick(150),{{4,true}},"expired chord passthrough");expect(e.process({4,false,160}),{{4,false}},"expired release");
        e=engine(c);e.process({4,true,100});expect(e.process({4,false,120}),{{4,true},{4,false}},"short failed chord tap preserved");
    }
    {
        auto c=base();c["profiles"][0]["layers"]={{{"name","nav"},{"trigger",{{"key","spacebar"}}},{"mode","hold"},{"map",{{"h","left_arrow"}}}}};auto e=engine(c);
        expect(e.process({44,true,1}),{},"layer trigger suppressed");expect(e.process({11,true,2}),{{80,true}},"layer map");e.process({44,false,3});expect(e.process({11,false,4}),{{80,false}},"map release stable after layer ends");expect(e.process({11,true,5}),{{11,true}},"layer ends");
        c["profiles"][0]["layers"][0]["mode"]="toggle";e=engine(c);e.process({44,true,1});e.process({44,false,2});expect(e.process({11,true,3}),{{80,true}},"toggle persists");
    }
    {
        auto c=base();auto m=basic("a","b");m["conditions"]={{{"type","frontmost_app_if"},{"bundle_identifiers",JSON::array({"^com\\.apple\\.Terminal$"})}}};c["profiles"][0]["rules"]={rule(m),rule(basic("a","c"))};auto e=engine(c);expect(e.process({4,true,1}),{{6,true}},"false context skips first");e.process({4,false,2});e.update_context({"com.apple.Terminal",""});expect(e.process({4,true,3}),{{5,true}},"first matching rule wins");
    }
    {
        auto c=base();auto set=basic("a","a");set["to"]={{{"set_variable",{{"name","nav"},{"value",1}}}}};auto m=basic("b","escape");m["conditions"]={{{"type","variable_if"},{"name","nav"},{"value",1}}};c["profiles"][0]["rules"]={rule(set),rule(m)};auto e=engine(c);e.process({4,true,0});e.process({4,false,1});expect(e.process({5,true,2}),{{41,true}},"variable action and condition");
    }
    {
        auto c=base();c["profiles"][0]["simple"]={{{"from",{{"key","a"}}},{"to",JSON::array({{{"key","c"}}})}},{{"from",{{"key","b"}}},{"to",JSON::array({{{"key","c"}}})}}};auto e=engine(c);expect(e.process({4,true,0}),{{6,true}},"shared output down");expect(e.process({5,true,1}),{},"reference counted down");expect(e.process({4,false,2}),{},"first release keeps shared key");expect(e.process({5,false,3}),{{6,false}},"last release");
        e.process({4,true,4});expect(e.release_all(5),{{6,false}},"failsafe releases");
    }
    {
        auto c=base();auto m=basic("a","b");m["from"]["modifiers"]={{"mandatory",JSON::array({"command"})}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);expect(e.process({4,true,1}),{{4,true}},"mandatory required");e.process({4,false,2});e.process({227,true,3});expect(e.process({4,true,4}),{{227,false},{5,true}},"modifier group matches and consumes left command");
    }
    {
        auto c=base();auto e=engine(c);e.process({224,true,1});e.process({226,true,2});e.process({227,true,3});e.process({41,true,4});auto o=e.tick(1004);check(e.paused(),"physical emergency chord pauses after hold");check(o.size>=3,"emergency releases modifiers");
    }
    {
        auto c=base();auto m=basic("a","b");m["to"]={{{"shell_command","true"}}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);auto o=e.process({4,true,1});check(o.size==0&&o.user_action_count==1,"user action queued without root execution");check(e.process({4,false,2}).user_action_count==0,"user action not repeated on release");
    }
    {
        auto c=base();auto m=basic("a","b");m["to"]={{{"sticky_modifier","left_shift"}}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);e.process({4,true,1});e.process({4,false,2});expect(e.process({6,true,3}),{{225,true},{6,true}},"sticky next key");expect(e.process({6,false,4}),{{6,false},{225,false}},"sticky clears after one key");expect(e.process({7,true,5}),{{7,true}},"sticky only once");
    }
    {
        auto c=base();auto m=basic("a","b");m["to"]={{{"key","b"}},{{"key","c"}},{{"key","d"}}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);expect(e.process({4,true,1}),{{5,true},{5,false},{6,true},{6,false},{7,true}},"to sequence taps preceding keys");expect(e.process({4,false,2}),{{7,false}},"only final sequence key held");
    }
    {
        auto c=base();auto m=basic("a","b");m["from"]["modifiers"]={{"mandatory",JSON::array({"command"})},{"optional",JSON::array({"shift"})}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);e.process({227,true,1});e.process({225,true,2});expect(e.process({4,true,3}),{{227,false},{5,true}},"mandatory consumed, optional retained");expect(e.process({4,false,4}),{{5,false},{227,true}},"held physical modifier restored");expect(e.process({227,false,5}),{{227,false}},"restored modifier releases");
    }
    {
        auto c=base();auto e=engine(c);expect(e.process({58,true,1}),{{0xc0070,true}},"default F1 media key");expect(e.process({58,false,2}),{{0xc0070,false}},"media release");
        c["profiles"][0]["devices"]={{{"id",{{"vendor_id",1},{"product_id",2}}},{"fn_keys_as_media",false}}};e=engine(c,{1,2});expect(e.process({58,true,1}),{{58,true}},"device standard F key mode");
    }
    {
        auto c=base();c["profiles"][0]["layers"]={{{"name","nav"},{"trigger",{{"key","spacebar"}}},{"mode","hold"},{"map",{{"h","left_arrow"}}}}};auto e=engine(c);e.process({44,true,0});expect(e.process({44,false,100}),{{44,true},{44,false}},"hold-layer trigger keeps normal tap");
    }
    {
        for(int keys=3;keys<=4;++keys){
            auto c=base();auto m=basic("a","escape");m["from"]={{"simultaneous",JSON::array()}};for(int i=0;i<keys;++i)m["from"]["simultaneous"].push_back({{"key",std::string(1,char('a'+i))}});c["profiles"][0]["rules"]={rule(m)};auto e=engine(c);
            for(int i=0;i<keys-1;++i)expect(e.process({Key(4+i),true,uint64_t(10*i)}),{},"multi-key chord waits for all members");expect(e.process({Key(3+keys),true,uint64_t(10*(keys-1))}),{{41,true}},"three/four key chord fires once");
            expect(e.process({Key(3+keys),false,100}),{{41,false}},"multi-key owner release");for(int i=0;i<keys-1;++i)expect(e.process({Key(4+i),false,uint64_t(110+i)}),{},"multi-key raw releases suppressed");
        }
    }
    {
        auto c=base();c["profiles"][0]["layers"]={{{"name","nav"},{"trigger",{{"key","spacebar"}}},{"mode","hold"},{"map",{{"h","left_arrow"}}}}};
        auto m=basic("a","b");m["from"]["modifiers"]={{"mandatory",JSON::array({"command"})},{"optional",JSON::array({"any"})}};m["to"]={{{"key","c"}},{{"key","d"}}};
        auto tap=basic("caps_lock","left_control");tap["to_if_alone"]={{{"key","escape"}}};auto held=basic("e","left_shift");held["to_if_held_down"]={{{"key","left_option"}}};held["to_after_key_up"]={{{"key","tab"}}};c["profiles"][0]["rules"]={rule(m),rule(tap),rule(held)};
        auto e=engine(c);std::array<bool,max_keys> emitted{};std::array<bool,256> physical{};uint32_t seed=20261021;const Key choices[]={4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,44,57,224,225,226,227,228,229,230,231};
        auto verify=[&](const Outputs& out){check(!out.overflow,"random stream output batch bounded");for(size_t n=0;n<out.size;++n){auto v=out.values[n];auto i=slot(v.key);check(v.down!=emitted[i],"no duplicate key-down or unmatched key-up");emitted[i]=v.down;}};
        for(int n=0;n<20000;++n){seed=seed*1664525u+1013904223u;Key k=choices[seed%(sizeof(choices)/sizeof(choices[0]))];physical[k]=!physical[k];verify(e.process({k,physical[k],uint64_t(n*7)}));}
        verify(e.release_all(150000));check(std::none_of(emitted.begin(),emitted.end(),[](bool down){return down;}),"random stream leaves no stuck output keys");
    }
    {
        auto c=base();auto m=basic("a","b");m["conditions"]={{{"type","device_if"},{"identifiers",JSON::array({{{"vendor_id",1},{"product_id",2},{"serial","A"}}})}}};c["profiles"][0]["rules"]={rule(m)};auto e=engine(c,{1,2,"B"});expect(e.process({4,true,0}),{{4,true}},"device serial mismatch");e=engine(c,{1,2,"A"});expect(e.process({4,true,0}),{{5,true}},"device serial condition");
        m["conditions"][0]["type"]="device_unless";c["profiles"][0]["rules"]={rule(m)};e=engine(c,{1,2,"A"});expect(e.process({4,true,0}),{{4,true}},"device unless");
        m["conditions"]={{{"type","input_source_if"},{"input_sources",JSON::array({{{"input_source_id","^com\\.apple\\.Japanese"}}})}}};c["profiles"][0]["rules"]={rule(m)};e=engine(c);e.update_context({"","com.apple.Japanese.Romaji"});expect(e.process({4,true,0}),{{5,true}},"input source condition");
        m["conditions"][0]["type"]="input_source_unless";c["profiles"][0]["rules"]={rule(m)};e=engine(c);e.update_context({"","com.apple.Japanese.Romaji"});expect(e.process({4,true,0}),{{4,true}},"input source unless");
        m["conditions"]={{{"type","keyboard_type_if"},{"keyboard_types",JSON::array({"jis"})}}};c["profiles"][0]["rules"]={rule(m)};c["profiles"][0]["devices"]={{{"id",{{"vendor_id",1},{"product_id",2}}},{"keyboard_type","jis"}}};e=engine(c,{1,2});expect(e.process({4,true,0}),{{5,true}},"keyboard type override condition");
        m["conditions"][0]["type"]="keyboard_type_unless";c["profiles"][0]["rules"]={rule(m)};e=engine(c,{1,2});expect(e.process({4,true,0}),{{4,true}},"keyboard type unless");
    }
    {
        auto c=base();auto m=basic("a","b");m["conditions"]={{{"type","device_if"},{"identifiers",JSON::array({{{"vendor_id",1},{"product_id",2},{"serial",nullptr}}})}}};c["profiles"][0]["rules"]={rule(m)};
        auto e=engine(c,{1,2,"A"});expect(e.process({4,true,0}),{{5,true}},"device condition null serial matches any serial");e=engine(c,{1,3,"A"});expect(e.process({4,true,0}),{{4,true}},"device condition null serial still checks product");
    }
    {
        auto rejects=[](const std::string& data){try{validate_config(data);}catch(const std::exception&){return true;}return false;};
        auto c=base();c["profiles"][0]["devices"]={{{"id",{{"vendor_id",1},{"product_id",2},{"serial",nullptr}}}}};check(!rejects(c.dump()),"validation accepts profiles without id and null serial");
        c["profiles"].push_back({{"name","Other"},{"selected",false},{"simple",JSON::array({{{"from",{{"key","nokey"}}},{"to",JSON::array({{{"key","a"}}})}}})}});check(rejects(c.dump()),"validation compiles unselected profiles");
        check(rejects(std::string(max_config_bytes+1,' ')),"validation enforces the size limit");
    }
    {
        auto c=base();auto m=basic("a","escape");m["from"]={{"simultaneous",JSON::array({{{"key","a"}},{{"key","a"}}})}};c["profiles"][0]["rules"]={rule(m)};bool rejected=false;
        try{(void)Program::compile(c,{});}catch(const std::runtime_error&){rejected=true;}check(rejected,"duplicate simultaneous key rejected");
    }
    // Benchmark only the transform; physical-to-virtual latency is a separate hardware test.
    auto c=base();for(int i=0;i<200;++i)c["profiles"][0]["rules"].push_back(rule(basic(i==199?"a":"b","c")));auto e=engine(c);std::vector<double> us;us.reserve(10000);
    for(int i=0;i<10000;++i){auto start=std::chrono::steady_clock::now();measure_allocations=true;auto o=e.process({4,(i%2)==0,uint64_t(i)});measure_allocations=false;auto end=std::chrono::steady_clock::now();check(o.size==1,"benchmark output");us.push_back(std::chrono::duration<double,std::micro>(end-start).count());}
    check(allocations==0,"no heap allocation while processing events");std::sort(us.begin(),us.end());std::cout<<"PASS "<<assertions<<" assertions; transform only: p50="<<us[5000]<<" us p99="<<us[9900]<<" us (200 rules, 10000 events)\n";
}
