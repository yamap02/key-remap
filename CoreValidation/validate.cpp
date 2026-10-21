#include "ReKeyValidation.h"
#include "Engine.hpp"
#include <cstring>
extern "C" int rekey_validate_json(const uint8_t* bytes,size_t length,char* error,size_t capacity){
    try{
        if(length>4*1024*1024)throw std::runtime_error("Configuration exceeds 4 MiB");
        auto config=rekey::JSON::parse(bytes,bytes+length);
        for(size_t pi=0;pi<config.at("profiles").size();++pi){
            auto candidate=config;for(size_t i=0;i<candidate["profiles"].size();++i)candidate["profiles"][i]["selected"]=(i==pi);
            (void)rekey::Program::compile(candidate,{});
            for(auto& device:candidate["profiles"][pi].value("devices",rekey::JSON::array())){
                auto id=device.at("id");std::string serial;if(id.contains("serial")&&!id["serial"].is_null())serial=id["serial"].get<std::string>();
                (void)rekey::Program::compile(candidate,{id.at("vendor_id"),id.at("product_id"),serial});
            }
        }
        return 1;
    }catch(const std::exception& e){if(error&&capacity){strncpy(error,e.what(),capacity-1);error[capacity-1]='\0';}return 0;}
}
