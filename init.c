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

// void dump_mem(void *addr, unsigned int length)
// {
//     unsigned char *p=(unsigned char*)addr;
//     unsigned char a;
// 
//     a=0;
//     while(length--){
//         if(!a)
//             printf("\n%04x: ", (unsigned int)p);
//         printf("%02x ", *(p++));
//         a = (a + 1) & 0x0F;
//     }
// 
//     printf("\n");
// }

void main(int argc, char *argv[])
{
    unsigned char *target;

    // keep sdcc quiet about our (currently) unused arguments
    argc;
    argv;

    printf("N8VEM UNA BIOS CP/M (Will Sowerbutts, 2014-07-04C)\n");

    if(!init_persist())
        return; // abort if incompatible

    // enumerate UNA disk units
    init_units();

    // prepare drive map
    init_drives();

    // prepare data structures for residual component
    prepare_drives();

    // relocate and load residual component
    target = allocate_memory(cpm_image_length);

#if 1
    // Force page alignment. Some applications require this.
    target = allocate_memory(((unsigned int)target) & 0xFF);    // expand, align.
#endif

    printf("\nLoading Residual CP/M at 0x%04X ...", target);
    if(!relocate_cpm(target)){
        printf("\n** Relocation failed (Residual CP/M image corrupt) **\n");
        halt();
    }
    printf(" booting.\n");

    // boot the residual CP/M system
    boot_cpm(target+BOOT_VECTOR_OFFSET);
}
