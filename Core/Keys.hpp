#pragma once
#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
namespace rekey {
using Key = uint32_t;
constexpr size_t max_keys=1536;
inline size_t slot(Key k){if(k<256)return k;auto usage=k&65535;auto page=k>>16;if(page==12&&usage<768)return 256+usage;if(page==0xff01&&usage<256)return 1024+usage;if(page==0xff&&usage<256)return 1280+usage;return max_keys;}
inline Key key_for_slot(size_t i){if(i<256)return Key(i);if(i<1024)return 0xc0000+Key(i-256);if(i<1280)return 0xff010000+Key(i-1024);return 0xff0000+Key(i-1280);}
inline const std::map<std::string, Key>& key_names() {
    static const auto keys = [] {
        std::map<std::string, Key> v;
        for (int i=0;i<26;++i) v[std::string(1, char('a'+i))]=4+i;
        for (int i=0;i<10;++i) v[std::string(1,"1234567890"[i])]=30+i;
        const char* standard[]={"return_or_enter","escape","delete_or_backspace","tab","spacebar","hyphen","equal_sign","open_bracket","close_bracket","backslash","non_us_pound","semicolon","quote","grave_accent_and_tilde","comma","period","slash","caps_lock"};
        for(int i=0;i<18;++i) v[standard[i]]=40+i;
        for(int i=1;i<=12;++i) v["f"+std::to_string(i)]=57+i;
        const char* extra[]={"print_screen","scroll_lock","pause","insert","home","page_up","delete_forward","end","page_down","right_arrow","left_arrow","down_arrow","up_arrow","keypad_num_lock","keypad_slash","keypad_asterisk","keypad_hyphen","keypad_plus","keypad_enter","keypad_1","keypad_2","keypad_3","keypad_4","keypad_5","keypad_6","keypad_7","keypad_8","keypad_9","keypad_0","keypad_period","non_us_backslash","application","power","keypad_equal_sign"};
        for(int i=0;i<34;++i) v[extra[i]]=70+i;
        for(int i=13;i<=24;++i) v["f"+std::to_string(i)]=91+i;
        for(int i=1;i<=5;++i) v["international"+std::to_string(i)]=134+i;
        v["japanese_kana"]=144;v["japanese_eisuu"]=145;
        const char* mods[]={"left_control","left_shift","left_option","left_command","right_control","right_shift","right_option","right_command"};
        for(int i=0;i<8;++i) v[mods[i]]=224+i;
        v["mute"]=0xc00e2;v["volume_increment"]=0xc00e9;v["volume_decrement"]=0xc00ea;v["play_or_pause"]=0xc00cd;v["fastforward"]=0xc00b3;v["rewind"]=0xc00b4;v["display_brightness_increment"]=0xc006f;v["display_brightness_decrement"]=0xc0070;
        v["mission_control"]=0xff010010;v["launchpad"]=0xff010004;v["spotlight"]=0xff010001;
        v["illumination_decrement"]=0xff0009;v["illumination_increment"]=0xff0008;v["fn"]=0xff0003;
        return v;
    }(); return keys;
}
inline Key key(const std::string& name) { auto i=key_names().find(name);if(i==key_names().end())throw std::runtime_error("Unsupported key: "+name);return i->second; }
inline uint8_t modifier(Key k) { return k>=224 && k<=231 ? uint8_t(1u << (k-224)) : 0; }
inline uint8_t modifier_mask(const std::string& name) {
    if(name=="command")return 0x88;if(name=="control")return 0x11;if(name=="shift")return 0x22;if(name=="option")return 0x44;
    return modifier(key(name));
}
}
