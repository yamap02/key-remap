#include "ReKeyValidation.h"
#include "Engine.hpp"
#include <cstring>
extern "C" int rekey_validate_json(const uint8_t* bytes,size_t length,char* error,size_t error_capacity){
    try{rekey::validate_config({reinterpret_cast<const char*>(bytes),length});return 1;}
    catch(const std::exception& e){if(error&&error_capacity){strncpy(error,e.what(),error_capacity-1);error[error_capacity-1]='\0';}return 0;}
}
