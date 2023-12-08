#include <stdint.h>
#include <string.h>

#include "rage1/banked.h"

struct main_shared_data_s main_shared_data;

void init_main_shared_data( struct main_shared_data_s *src ) {
    memcpy( &main_shared_data, src, sizeof( main_shared_data ) );
}
