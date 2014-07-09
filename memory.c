#include <stdio.h>
#include "units.h"
#include "memory.h"
#include "bios.h"

unsigned char *alloc_ptr = 0xFF00; // start below the UBIOS stub
persist_t *persist = 0;

void *ubios_malloc(unsigned int size)
{
    reg_in.b.C = UNABIOS_MALLOC;
    reg_in.w.DE = size;
    bios_call(&reg_out, &reg_in);
    if(reg_out.b.C){
        printf("UNA malloc failed\n");
        return 0;
    }
    return (void*)reg_out.w.HL;
}

void *allocate_memory(unsigned int size)
{
    // printf("allocate_memory(%d)\n", size);
    alloc_ptr = alloc_ptr - size;
    return alloc_ptr;
}

bool init_persist(void)
{
    // this is always allocated first, so it should always be in the same place
    persist = allocate_memory(sizeof(persist_t));

    if(persist->signature != PERSIST_SIGNATURE){
        persist->signature = PERSIST_SIGNATURE;
        persist->version = PERSIST_VERSION;
        if(!(persist->ubios_sector_buffer = ubios_malloc(0x200)))
            return false;
        if(!(persist->ubios_ccp_clone = ubios_malloc(0x800)))
            return false;
        persist->drive_count = 0;
        persist->drive_map = 0;
        persist->config_unit = NO_UNIT;
    }else{
        if(persist->version != PERSIST_VERSION){
            printf("Persistent data: Incompatible version!\n");
            return false;
        }
    }
    return true;
}
