#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "cpmimage.h"
#include "relocate.h"
#include "units.h"
#include "config.h"
#include "drives.h"
#include "memory.h"
#include "bios.h"
#include "version.h"

union regs reg_in, reg_out;
bool update_saved_config = false;
bool page_align = true;

bool cpm_loaded(void)
{
    return (*((unsigned char *)BDOS_ENTRY_ADDR) == 0xC3); // 0xC3 == JP instruction
}

void write_signature(void)
{
    *((unsigned int *)CPM_SIGNATURE_ADDR)  = 0x05B1; // Identify UNA CP/M
}

void halt(void)
{
    __asm
        di
        halt
    __endasm;
}

void cpminit(char *cmdline)
{
    unsigned char *target;

    // hello, world.
    printf("N8VEM %s\n", software_version_string);

    // prepare the high memory structures
    if(!init_persist())
        return; // abort now if we are incompatible

    // enumerate UNA disk units
    init_units();
    printf("\n");

    // prepare drive map
    init_drives();

    // look for a configuration block
    find_configuration_unit();

    // ensure command line is in upper case
    for(target = cmdline; *target; target++)
        *target = toupper(*target);

    // try to load config from command line
    if(!config_load_from_string(cmdline)){
        if(cpm_loaded())
            return; // error parsing command line -- abort.
        // can't abort if no CP/M loaded to return to
    }

    if(drives_count_valid() == 0){
        // no disk mapping on the command line; load config from disk instead.
        config_load_from_unit(persist.config_unit);
    }

    if(update_saved_config){
        if(persist.config_unit == NO_UNIT){
            printf("No existing saved configuration detected. Use \"/CONFDISK=<disk> /SAVE\".\n");
            if(cpm_loaded())
                return; // abort
            // can't abort; plough ahead
        }else{
            config_save_to_unit(persist.config_unit);
        }
    }

    // Now we start to scribble on high memory. There's no turning back after this point.

    // prepare data structures for residual component
    prepare_drives();

    // relocate and load residual component
    target = allocate_memory(cpm_image_length);

    if(page_align){
        // Force page alignment. Some (many?) applications require this.
        target = allocate_memory(((unsigned int)target) & 0xFF);    // expand, align. wasteful :(
    }

    printf("\nLoading Residual CP/M at 0x%04X ...", target);
    if(!relocate_cpm(target)){
        printf("\n** Relocation failed (Residual CP/M image corrupt) **\n");
        halt();
    }
    printf(" done.\n");

    // write in the persist_t structure
    write_persist(target, cpm_image_length);

    // write signatures in memory to identify us
    write_signature();

    // boot the residual CP/M system
    boot_cpm(target+BOOT_VECTOR_OFFSET);
}
