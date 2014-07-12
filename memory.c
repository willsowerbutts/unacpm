#include <stdio.h>
#include <string.h>
#include "units.h"
#include "memory.h"
#include "bios.h"

/* We allocate memory from the top down. We start allocation immediately below
 * the UNA BIOS stub. The first two bytes we allocate are for 'persist_ptr', a
 * pointer to the persistent memory structure passed to the CP/M residual, so
 * that we can find it again on the next iteration. 'persist' is a copy of this
 * structure, kept in normal data memory and copied into the next iteration of
 * the CP/M residual.
 */
 
unsigned char *alloc_ptr;
persist_t **persist_ptr;
persist_t persist;

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

void write_persist(unsigned char *target, unsigned int cpm_image_length)
{
    target = target + cpm_image_length - sizeof(persist_t);
    memcpy(target, &persist, sizeof(persist_t));
    (*persist_ptr) = (persist_t*)target;

}

bool init_persist(void)
{
    // find the lower bound of the UBIOS stub (HMA)
    reg_in.b.C = UNABIOS_GET_HMA;
    bios_call(&reg_out, &reg_in);
    alloc_ptr = (void*)reg_out.w.HL;

    // this is always allocated first, so it should always be in the same place
    persist_ptr = (persist_t**)allocate_memory(sizeof(persist_t*));

    if(*persist_ptr == NULL || (*persist_ptr)->signature != PERSIST_SIGNATURE){
        // create new instance
        persist.signature = PERSIST_SIGNATURE;
        persist.version = PERSIST_VERSION;
        if(!(persist.ubios_sector_buffer = ubios_malloc(0x200)))
            return false;
        if(!(persist.ubios_ccp_clone = ubios_malloc(0x800)))
            return false;
        persist.drive_count = 0;
        persist.drive_map = 0;
        persist.config_unit = NO_UNIT;
    }else{
        if((*persist_ptr)->version != PERSIST_VERSION){
            printf("Persistent data: Incompatible version!\n");
            return false;
        }
        memcpy(&persist, *persist_ptr, sizeof(persist_t));
    }
    return true;
}
