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

void dump_mem(void *addr, unsigned int length)
{
    unsigned char *p=(unsigned char*)addr;
    unsigned char a;

    a=0;
    while(length--){
        if(!a)
            printf("\n%04x: ", (unsigned int)p);
        printf("%02x ", *(p++));
        a = (a + 1) & 0x0F;
    }

    printf("\n");
}

#if 0
void test(void)
{
    unsigned char unit = 0;
    unsigned int sector, secmax;

    // get capacity
    reg_in.b.C = 0x45;
    reg_in.b.B = unit;
    reg_in.w.DE = 0;
    bios_call(&reg_out, &reg_in);
    if(reg_out.b.C){
        printf("Get capacity error: %02x\n", reg_out.b.C);
        return;
    }
    if(reg_out.w.DE){
        printf("Too large to test\n");
        return;
    }
    secmax = reg_out.w.HL;

    printf("unit %d testing %d sectors\n", unit, secmax);

    for(sector=0; sector<secmax; sector++){
        printf("Write sector %d\n", sector);
        // set LBA
        reg_in.b.C = 0x41;
        reg_in.b.B = unit;
        reg_in.w.DE = 0;
        reg_in.w.HL = sector;
        bios_call(&reg_out, &reg_in);
        if(reg_out.b.C){
            printf("Set LBA error: %02x\n", reg_out.b.C);
            return;
        }

        // transfer sector
        reg_in.b.C = 0x43;
        reg_in.b.B = unit;
        reg_in.w.DE = 0x8000; // unused chunk of memory
        reg_in.b.L = 1;
        bios_call(&reg_out, &reg_in);
        if(reg_out.b.C){
            printf("Write sector error: %02x\n", reg_out.b.C);
            return;
        }
    }
    printf("Done.\n");
}
#endif

#if 0

#define Z180_IO_BASE (0x40)
#include <z180/z180.h>

void test(void)
{
    reg_in.b.C = 0xFA;
    reg_in.b.B = 5;
    bios_call(&reg_out, &reg_in);
    printf("DE=%02x HL=%02x\n", reg_out.w.DE, reg_out.w.HL);
    printf("CBAR=%02x BBR=%02x CBR=%02x\n", CBAR, BBR, CBR);
}
#endif

void main(int argc, char *argv[])
{
    unsigned char *target;

    // keep sdcc quiet about our (currently) unused arguments
    argc;
    argv;

    printf("N8VEM UNA BIOS CP/M (Will Sowerbutts, 2014-07-02)\n");

#if 0
    test();
#endif

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

    // If we require CP/M to be page aligned. It is not safe to call
    // allocate_memory() again after we do this. It is not clear if
    // CP/M actually needs to be page aligned, I assume it may be for
    // some applications.
#if 0
    target = (unsigned char*)(((unsigned int)target) & 0xFF00);
#endif

    printf("\nLoading Residual CP/M at 0x%04X ...", target);
    if(relocate_cpm(target) != cpm_image_length){
        printf("\n** Relocation failed (Residual CP/M image corrupt) **\n");
        halt();
    }
    printf(" booting.\n");

    // dump_mem((char*)0x0000, 0x200);
    // dump_mem((char*)target, 0xFF00-(unsigned int)target);

    // boot the residual CP/M system
    boot_cpm(target+BOOT_VECTOR_OFFSET);
}
