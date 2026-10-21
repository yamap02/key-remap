#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int rekey_validate_json(const uint8_t* bytes, size_t length, char* error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
