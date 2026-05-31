// types.h — cpctelera compatibility shim for z88dk builds.
//
// cpctelera's cpct_img2tileset-generated .c/.h files include <types.h>
// for the u8/u16/i8/i16 typedefs.  This stub provides those typedefs
// when building outside cpctelera (e.g. with z88dk's +cpc target).
//
// Place this file in the include search path so the generated headers
// can find it.  In the R3 PoC, -Iassets achieves this.
#ifndef CPCTELERA_TYPES_SHIM_H
#define CPCTELERA_TYPES_SHIM_H

#include <stdint.h>

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef int8_t   i8;
typedef int16_t  i16;
typedef int32_t  i32;

#endif /* CPCTELERA_TYPES_SHIM_H */
