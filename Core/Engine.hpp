#pragma once
#include "Keys.hpp"
#include <nlohmann/json.hpp>
#include <array>
#include <bitset>
#include <vector>
#include <regex>
#include <algorithm>
namespace rekey {
using JSON = nlohmann::json;
constexpr size_t max_actions=16, max_rules=512, max_layers=32, max_variables=64;

struct Input { Key key=0;bool down=false;uint64_t time_ms=0;uint32_t device=0; };
struct Output { Key key=0;bool down=false;uint64_t time_ms=0;int rule=-1; };
struct Outputs {
    std::array<Output,1024> values{}; size_t size=0; bool overflow=false;
    std::array<int,64> user_actions{};size_t user_action_count=0;
    void push(Key key,bool down,uint64_t t,int rule=-1) { if(size<values.size())values[size++]={key,down,t,rule};else overflow=true; }
};
struct Identity { int vendor=0,product=0;std::string serial;bool builtin=false;std::string keyboard_type="unknown"; };
struct Context { std::string app,input_source; };
struct Condition {
    enum Kind { app, device, source, keyboard, variable, layer } kind=app;
    bool unless=false;std::vector<std::regex> patterns;struct DeviceMatch { int vendor,product;std::string serial; };std::vector<DeviceMatch> devices;std::vector<std::string> strings;int index=0,value=0;
};
struct Action { enum Kind { key, variable, layer, sticky, user } kind=key; Key code=0;uint8_t modifiers=0;int index=0,value=0; };
struct Actions { std::array<Action,max_actions> values{};size_t size=0;void add(Action a){if(size==max_actions)throw std::runtime_error("Too many actions (maximum 16)");values[size++]=a;} };
struct Rule {
    std::string name;
    std::array<Key,4> from{};size_t from_count=0;
    std::array<uint8_t,8> mandatory{};size_t mandatory_count=0;uint8_t allowed=0;bool any_modifiers=false,any_key=false;
    Actions to,alone,held,after;
    uint64_t alone_ms=200,held_ms=500,chord_ms=50;
    std::vector<Condition> conditions;bool context_enabled=true;
};
struct LayerMap { std::string name;Key trigger=0;bool toggle=false;std::array<Key,max_keys> map{}; };
struct Program {
    std::array<Key,max_keys> simple{};
    std::vector<JSON> user_actions;
    std::vector<Rule> rules;std::vector<LayerMap> layers;std::vector<std::string> variables;
    std::array<std::vector<uint16_t>,max_keys> by_key;
    std::string keyboard_type="unknown";uint64_t layer_tap_ms=200;bool ignore=false,disable_builtin=false,fn_media=true;
    int variable_index(const std::string& name) { auto i=std::find(variables.begin(),variables.end(),name);if(i!=variables.end())return int(i-variables.begin());if(variables.size()==max_variables)throw std::runtime_error("Too many variables");variables.push_back(name);return int(variables.size()-1); }
    int layer_index(const std::string& name) const { for(size_t i=0;i<layers.size();++i)if(layers[i].name==name)return int(i);throw std::runtime_error("Unknown layer: "+name); }
    Actions actions(const JSON& a) {
        if(!a.is_array())throw std::runtime_error("Actions must be an array");Actions out;
        for(auto& j:a) {
            Action v;
            if(j.contains("key")) { v.code=rekey::key(j.at("key"));for(auto& m:j.value("modifiers",JSON::array())) { auto mask=modifier_mask(m);v.modifiers|=(mask&15)?(mask&15):mask; } }
            else if(j.contains("set_variable")) {v.kind=Action::variable;auto& x=j.at("set_variable");v.index=variable_index(x.at("name"));v.value=x.at("value");}
            else if(j.contains("layer")) {v.kind=Action::layer;auto& x=j.at("layer");v.index=layer_index(x.is_string()?x.get<std::string>():x.at("name").get<std::string>());v.value=x.is_string()?1:x.value("value",1);}
            else if(j.contains("sticky_modifier")) {v.kind=Action::sticky;v.code=rekey::key(j.at("sticky_modifier"));if(!modifier(v.code))throw std::runtime_error("Invalid sticky modifier");}
            else if(j.contains("shell_command")||j.contains("open_app")||j.contains("select_input_source")||j.contains("notify")) { v.kind=Action::user;v.index=int(user_actions.size());user_actions.push_back(j); }
            else throw std::runtime_error("Unsupported action");
            out.add(v);
        } return out;
    }
    static Program compile(const JSON& config,const Identity& device) {
        if(config.at("schema_version")!=1)throw std::runtime_error("Unsupported schema version");
        auto profiles=config.at("profiles");auto pi=std::find_if(profiles.begin(),profiles.end(),[](auto& p){return p.value("selected",false);});if(pi==profiles.end())throw std::runtime_error("No selected profile");
        auto p=*pi;Program out;JSON specific=JSON::object();
        for(auto& d:p.value("devices",JSON::array())) {auto id=d.at("id");if(id.at("vendor_id")==device.vendor && id.at("product_id")==device.product && (!id.contains("serial") || id["serial"].is_null() || id["serial"]==device.serial)){specific=d;break;}}
        out.keyboard_type=specific.value("keyboard_type",std::string("auto"));if(out.keyboard_type=="auto")out.keyboard_type=device.keyboard_type;
        out.ignore=specific.value("ignore",false);out.disable_builtin=specific.value("disable_builtin_when_connected",false);out.fn_media=specific.value("fn_keys_as_media",true);
        auto combined=[&](const char* field){JSON a=specific.value(field,JSON::array());for(auto& x:p.value(field,JSON::array()))a.push_back(x);return a;};
        for(auto& s:combined("simple")) {auto f=rekey::key(s.at("from").at("key"));auto& targets=s.at("to");if(targets.size()!=1)throw std::runtime_error("Simple mapping needs one target");auto k=slot(f);if(k==max_keys)throw std::runtime_error("Key outside supported range");if(!out.simple[k])out.simple[k]=rekey::key(targets[0].at("key"));}
        for(auto& l:combined("layers")) {
            if(out.layers.size()==max_layers)throw std::runtime_error("Too many layers");
            auto name=l.at("name").get<std::string>();if(std::any_of(out.layers.begin(),out.layers.end(),[&](auto& x){return x.name==name;}))continue;
            LayerMap lm;lm.name=name;lm.trigger=rekey::key(l.at("trigger").at("key"));auto mode=l.at("mode").get<std::string>();if(mode!="hold" && mode!="toggle")throw std::runtime_error("Invalid layer mode");lm.toggle=mode=="toggle";
            for(auto i=l.at("map").begin();i!=l.at("map").end();++i)lm.map[slot(rekey::key(i.key()))]=rekey::key(i.value());out.layers.push_back(lm);
        }
        auto thresholds=config.at("global").at("thresholds_ms");out.layer_tap_ms=thresholds.at("alone");
        for(auto& group:combined("rules"))for(auto& m:group.at("manipulators")) {
            if(out.rules.size()==max_rules)throw std::runtime_error("Too many manipulators");
            if(m.at("type")!="basic")throw std::runtime_error("Unsupported manipulator");Rule r;r.name=group.at("name");auto f=m.at("from");
            if(f.contains("simultaneous")) { for(auto& k:f.at("simultaneous")){if(r.from_count==4)throw std::runtime_error("Maximum four simultaneous keys");r.from[r.from_count++]=rekey::key(k.at("key"));}if(r.from_count<2)throw std::runtime_error("Simultaneous requires two to four keys"); }
            else if(f.contains("key")) {r.from[0]=rekey::key(f.at("key"));r.from_count=1;}
            else if(f.value("any",std::string())=="key_code")r.any_key=true;
            else throw std::runtime_error("Missing from key");
            auto mods=f.value("modifiers",JSON::object());for(auto& mod:mods.value("mandatory",JSON::array())) {if(r.mandatory_count==8)throw std::runtime_error("Too many mandatory modifiers");auto mask=modifier_mask(mod);r.mandatory[r.mandatory_count++]=mask;r.allowed|=mask;}
            for(auto& mod:mods.value("optional",JSON::array())) {if(mod=="any")r.any_modifiers=true;else r.allowed|=modifier_mask(mod);}
            r.alone_ms=thresholds.at("alone");r.held_ms=thresholds.at("held_down");r.chord_ms=thresholds.at("simultaneous");
            auto params=m.value("parameters",JSON::object());r.alone_ms=params.value("basic.to_if_alone_timeout_milliseconds",r.alone_ms);r.held_ms=params.value("basic.to_if_held_down_threshold_milliseconds",r.held_ms);r.chord_ms=params.value("basic.simultaneous_threshold_milliseconds",r.chord_ms);
            if(!r.alone_ms||r.alone_ms>5000||!r.held_ms||r.held_ms>5000||!r.chord_ms||r.chord_ms>500)throw std::runtime_error("Invalid rule thresholds");
            r.to=out.actions(m.value("to",JSON::array()));r.alone=out.actions(m.value("to_if_alone",JSON::array()));r.held=out.actions(m.value("to_if_held_down",JSON::array()));r.after=out.actions(m.value("to_after_key_up",JSON::array()));
            for(auto& c:m.value("conditions",JSON::array())) {
                Condition condition;auto type=c.at("type").get<std::string>();condition.unless=type.ends_with("_unless");
                if(type=="frontmost_app_if"||type=="frontmost_app_unless") {condition.kind=Condition::app;for(auto& pat:c.at("bundle_identifiers"))condition.patterns.emplace_back(pat.get<std::string>());}
                else if(type=="input_source_if"||type=="input_source_unless") {condition.kind=Condition::source;for(auto& src:c.at("input_sources")){if(!src.contains("input_source_id"))throw std::runtime_error("input_source_id is required");condition.patterns.emplace_back(src.at("input_source_id").get<std::string>());}}
                else if(type=="device_if"||type=="device_unless") {condition.kind=Condition::device;for(auto& id:c.at("identifiers"))condition.devices.push_back({id.at("vendor_id"),id.at("product_id"),id.contains("serial")&&!id.at("serial").is_null()?id.at("serial").get<std::string>():std::string()});}
                else if(type=="keyboard_type_if"||type=="keyboard_type_unless") {condition.kind=Condition::keyboard;condition.strings=c.at("keyboard_types").get<std::vector<std::string>>();}
                else if(type=="variable_if"||type=="variable_unless") {condition.kind=Condition::variable;condition.index=out.variable_index(c.at("name"));condition.value=c.at("value");}
                else if(type=="layer_if"||type=="layer_unless") {condition.kind=Condition::layer;condition.index=out.layer_index(c.at("name"));condition.value=1;}
                else throw std::runtime_error("Unsupported condition: "+type);
                r.conditions.push_back(std::move(condition));
            }
            out.rules.push_back(std::move(r));
        }
        for(size_t i=0;i<out.rules.size();++i) {auto& r=out.rules[i];if(r.any_key){for(auto& list:out.by_key)list.push_back(uint16_t(i));}else for(size_t j=0;j<r.from_count;++j)out.by_key[slot(r.from[j])].push_back(uint16_t(i));}
        return out;
    }
};
class Engine {
    struct Press { bool down=false,alone=true,held=false,pending=false,suppressed=false,plain_emitted=false;uint8_t suppress_mask=0;Key mapped=0;uint64_t started=0;int rule=-1,layer=-1; };
    Program program_;Identity identity_;std::array<Press,max_keys> presses_{};std::array<int,max_variables> variables_{};std::bitset<max_layers> layers_;std::array<uint16_t,max_keys> output_counts_{};std::array<uint16_t,8> suppressions_{};uint8_t sticky_=0;Key sticky_owner_=0;
    bool paused_=false;uint64_t emergency_start_=0;
    void emit(Key k,bool down,uint64_t t,Outputs& out,int rule=-1) {
        auto i=slot(k);if(i>=max_keys)return;
        auto& count=output_counts_[i];if(down){if(count++==0)out.push(k,true,t,rule);}else if(count && --count==0)out.push(k,false,t,rule);
    }
    void actions(const Actions& aa,bool down,uint64_t t,Outputs& out,int rule) {
        auto apply=[&](const Action& a,bool direction) {
            switch(a.kind) {
            case Action::key:
                if(direction){for(int i=0;i<8;++i)if(a.modifiers&(1<<i))emit(224+i,true,t,out,rule);emit(a.code,true,t,out,rule);}
                else {emit(a.code,false,t,out,rule);for(int i=7;i>=0;--i)if(a.modifiers&(1<<i))emit(224+i,false,t,out,rule);}break;
            case Action::variable:if(direction)variables_[a.index]=a.value;break;
            case Action::layer:if(direction)layers_[a.index]=a.value!=0;break;
            case Action::sticky:if(direction)sticky_|=modifier(a.code);break;
            case Action::user:if(direction){if(out.user_action_count<out.user_actions.size())out.user_actions[out.user_action_count++]=a.index;else out.overflow=true;}break;
            }
        };
        if(down){for(size_t i=0;i<aa.size;++i){const auto& a=aa.values[i];apply(a,true);if(a.kind==Action::key && i+1<aa.size)apply(a,false);}}
        else {for(size_t i=aa.size;i>0;--i){const auto& a=aa.values[i-1];if(a.kind!=Action::key || i==aa.size)apply(a,false);}}
    }
    void tap(const Actions& aa,uint64_t t,Outputs& out,int rule){actions(aa,true,t,out,rule);actions(aa,false,t,out,rule);}
    uint8_t modifiers()const { uint8_t m=0;for(const auto& p:presses_)if(p.down)m|=modifier(p.mapped);return m; }
    bool matches(const Rule& r)const {
        if(!r.context_enabled)return false;auto mods=modifiers();for(size_t i=0;i<r.mandatory_count;++i)if(!(mods&r.mandatory[i]))return false;
        // The pressed modifier itself is a from key, not an extra required modifier.
        for(size_t i=0;i<r.from_count;++i)mods&=~modifier(r.from[i]);
        if(!r.any_modifiers && (mods&~r.allowed))return false;
        for(auto& c:r.conditions){bool hit=false;if(c.kind==Condition::variable)hit=variables_[c.index]==c.value;else if(c.kind==Condition::layer)hit=layers_[c.index];else continue;if(hit==c.unless)return false;}
        return true;
    }
    void activate(size_t i,int rule,uint64_t t,Outputs& out) {
        auto& p=presses_[i];p.pending=false;p.rule=rule;auto& r=program_.rules[rule];
        uint8_t physical=modifiers();for(size_t n=0;n<r.mandatory_count;++n)p.suppress_mask|=r.mandatory[n]&physical;
        for(size_t n=0;n<8;++n)if(p.suppress_mask&(1<<n))if(suppressions_[n]++==0){for(auto& press:presses_)if(press.down&&press.mapped==224+n&&press.plain_emitted){emit(Key(224+n),false,t,out,rule);press.plain_emitted=false;}}
        actions(r.to,true,t,out,rule);
    }
    bool resolveRule(size_t i,uint64_t t,Outputs& out,bool allow_chord) {
        auto& p=presses_[i];auto mappedSlot=slot(p.mapped);if(mappedSlot>=max_keys)return false;
        bool waiting=false;
        for(auto index:program_.by_key[mappedSlot]) {
            auto& r=program_.rules[index];if(!matches(r))continue;
            if(r.from_count>1) {
                if(!allow_chord)continue;
                std::array<size_t,4> members{};size_t count=0;uint64_t first=t,last=0;
                for(size_t k=0;k<r.from_count;++k)for(size_t n=0;n<presses_.size();++n){auto& q=presses_[n];if(q.down&&q.mapped==r.from[k]&&q.rule<0&&!q.suppressed&&!q.plain_emitted&&q.layer<0){members[count++]=n;first=std::min(first,q.started);last=std::max(last,q.started);break;}}
                if(count==r.from_count && last-first<=r.chord_ms) {
                    for(size_t k=0;k<count;++k){auto& q=presses_[members[k]];q.pending=false;q.suppressed=true;q.rule=-1;}
                    p.suppressed=false;activate(i,index,t,out);return true;
                }
                if(t-p.started<r.chord_ms)waiting=true;
                continue;
            }
            if(waiting){p.pending=true;return true;}
            activate(i,index,t,out);return true;
        }
        if(waiting){p.pending=true;return true;}return false;
    }
    void plain(size_t i,uint64_t t,Outputs& out) {
        auto& p=presses_[i];
        for(size_t l=0;l<program_.layers.size();++l)if(program_.layers[l].trigger==p.mapped){auto& lm=program_.layers[l];p.layer=int(l);layers_[l]=lm.toggle?!layers_[l]:true;return;}
        for(size_t l=program_.layers.size();l>0;--l)if(layers_[l-1]){auto k=slot(p.mapped);if(k<max_keys&&program_.layers[l-1].map[k]){p.mapped=program_.layers[l-1].map[k];break;}}
        if(program_.fn_media&&p.mapped>=58&&p.mapped<=69&&!presses_[slot(0xff0003)].down){
            constexpr Key media[]={0xc0070,0xc006f,0xff010010,0xff010004,0xff0009,0xff0008,0xc00b4,0xc00cd,0xc00b3,0xc00e2,0xc00ea,0xc00e9};p.mapped=media[p.mapped-58];
        }
        if(sticky_&&!modifier(p.mapped)){for(int n=0;n<8;++n)if(sticky_&(1<<n))emit(224+n,true,t,out);sticky_owner_=p.mapped;}
        auto mod=modifier(p.mapped);bool suppressed_modifier=false;for(size_t n=0;n<8;++n)if((mod&(1<<n))&&suppressions_[n])suppressed_modifier=true;
        if(!suppressed_modifier){emit(p.mapped,true,t,out);p.plain_emitted=true;}
    }
public:
    explicit Engine(Program p,Identity identity={}):program_(std::move(p)),identity_(std::move(identity)){identity_.keyboard_type=program_.keyboard_type;}
    const Program& program()const{return program_;}
    bool paused()const{return paused_;}
    uint8_t input_modifiers()const {uint8_t m=0;for(size_t i=224;i<232;++i)if(presses_[i].down)m|=1<<(i-224);return m;}
    uint8_t output_modifiers()const {uint8_t m=0;for(size_t i=224;i<232;++i)if(output_counts_[i])m|=1<<(i-224);return m;}
    void update_context(const Context& context) {
        for(auto& r:program_.rules){r.context_enabled=true;for(auto& c:r.conditions){bool hit=false;switch(c.kind){
            case Condition::app:case Condition::source:{auto& s=c.kind==Condition::app?context.app:context.input_source;for(auto& pat:c.patterns)if(std::regex_search(s,pat)){hit=true;break;}break;}
            case Condition::device:for(auto& id:c.devices)if(id.vendor==identity_.vendor&&id.product==identity_.product&&(id.serial.empty()||id.serial==identity_.serial))hit=true;break;
            case Condition::keyboard:hit=std::find(c.strings.begin(),c.strings.end(),identity_.keyboard_type)!=c.strings.end();break;
            default:continue;
        }if(hit==c.unless){r.context_enabled=false;break;}}}
    }
    Outputs release_all(uint64_t t) {Outputs out;for(size_t i=0;i<max_keys;++i)if(output_counts_[i]){Key k=key_for_slot(i);out.push(k,false,t);output_counts_[i]=0;}presses_={};layers_.reset();variables_={};suppressions_={};sticky_=0;sticky_owner_=0;emergency_start_=0;return out;}
    Outputs tick(uint64_t t) {
        Outputs out;
        if(emergency_start_ && t-emergency_start_>=1000){out=release_all(t);paused_=true;emergency_start_=0;return out;}
        for(size_t i=0;i<max_keys;++i){auto& p=presses_[i];if(!p.down)continue;
            if(p.pending){bool wait=false;for(auto ri:program_.by_key[slot(p.mapped)])if(program_.rules[ri].from_count>1 && matches(program_.rules[ri]) && t-p.started<program_.rules[ri].chord_ms)wait=true;
                if(!wait){p.pending=false;if(!resolveRule(i,t,out,false))plain(i,t,out);}}
            if(p.rule>=0&&!p.held){auto& r=program_.rules[p.rule];if(r.held.size && t-p.started>=r.held_ms){actions(r.to,false,t,out,p.rule);actions(r.held,true,t,out,p.rule);p.held=true;}}
        }return out;
    }
    Outputs process(Input e) {
        Outputs out=tick(e.time_ms);auto i=slot(e.key);if(i>=max_keys)return out;auto& p=presses_[i];
        if(paused_||program_.ignore){out.push(e.key,e.down,e.time_ms);return out;}
        if(e.down){if(p.down)return out;for(auto& q:presses_)if(q.down)q.alone=false;p={};p.down=true;p.started=e.time_ms;p.mapped=program_.simple[i]?program_.simple[i]:e.key;
            uint8_t mods=0;for(size_t mi=224;mi<232;++mi)if(presses_[mi].down)mods|=modifier(Key(mi));if((mods&0x11) && (mods&0x44) && (mods&0x88) && e.key==41)emergency_start_=e.time_ms;
            if(!resolveRule(i,e.time_ms,out,true))plain(i,e.time_ms,out);
        } else {
            if(!p.down)return out;if(e.key==41||modifier(e.key))emergency_start_=0;
            if(p.pending){p.pending=false;if(!resolveRule(i,e.time_ms,out,false))plain(i,e.time_ms,out);}
            if(p.layer>=0){if(!program_.layers[p.layer].toggle){layers_[p.layer]=false;if(p.alone&&e.time_ms-p.started<=program_.layer_tap_ms){emit(p.mapped,true,e.time_ms,out);emit(p.mapped,false,e.time_ms,out);}}}
            else if(p.rule>=0){auto& r=program_.rules[p.rule];actions(p.held?r.held:r.to,false,e.time_ms,out,p.rule);if(p.alone&&!p.held&&e.time_ms-p.started<=r.alone_ms)tap(r.alone,e.time_ms,out,p.rule);tap(r.after,e.time_ms,out,p.rule);}
            else if(!p.suppressed&&p.plain_emitted)emit(p.mapped,false,e.time_ms,out);
            if(sticky_owner_==p.mapped){for(int n=0;n<8;++n)if(sticky_&(1<<n))emit(224+n,false,e.time_ms,out);sticky_=0;sticky_owner_=0;}
            for(size_t n=0;n<8;++n)if(p.suppress_mask&(1<<n)){if(suppressions_[n]&&--suppressions_[n]==0){for(auto& press:presses_)if(press.down&&press.mapped==224+n&&press.rule<0&&!press.plain_emitted){emit(Key(224+n),true,e.time_ms,out);press.plain_emitted=true;}}}
            p={};
        }return out;
    }
};
}
