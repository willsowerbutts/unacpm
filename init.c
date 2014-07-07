#include <stdio.h>
#include <string.h>
#include "cpmimage.h"
#include "relocate.h"
#include "units.h"
#include "drives.h"
#include "memory.h"
#include "bios.h"

union regs reg_in, reg_out;

void halt(void)
{
    __asm
        di
        halt
    __endasm;
}

void main(int argc, char *argv[])
{
    unsigned char *target;

    // keep sdcc quiet about our (currently) unused arguments
    printf("N8VEM UNA BIOS CP/M (Will Sowerbutts, 2014-07-06)\n");

    if(!init_persist())
        return; // abort if incompatible

    // enumerate UNA disk units
    init_units();
    printf("\n");

    // prepare drive map
    init_drives();
    if(argc > 1){
        if(drives_load_mapping(argc-1, argv+1))
            return; // error parsing command line
    }

    // prepare data structures for residual component
    prepare_drives();

    // relocate and load residual component
    target = allocate_memory(cpm_image_length);

    // Force page alignment. Some applications require this.
    target = allocate_memory(((unsigned int)target) & 0xFF);    // expand, align.  wasteful :(

    printf("\nLoading Residual CP/M at 0x%04X ...", target);
    if(!relocate_cpm(target)){
        printf("\n** Relocation failed (Residual CP/M image corrupt) **\n");
        halt();
    }
    printf(" booting.\n");

    // boot the residual CP/M system
    boot_cpm(target+BOOT_VECTOR_OFFSET);
}
