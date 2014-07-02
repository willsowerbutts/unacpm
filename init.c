#include <stdio.h>
#include <string.h>
#include "cpmimage.h"
#include "relocate.h"
#include "units.h"
#include "drives.h"
#include "memory.h"
#include "bios.h"

union regs reg_in, reg_out;

void dump_mem(void *addr, unsigned int length)
{
    unsigned char *p=(unsigned char*)addr;
    unsigned char a;

    a=0;
    while(length--){
        printf("%02x ", *(p++));
        a++;
        if(a==16){
            printf("\n");
            a=0;
        }
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

void main(int argc, char *argv[])
{
    unsigned char *target;

    // keep sdcc quiet about our (currently) unused arguments
    argc;
    argv;

    printf("N8VEM UNA BIOS CP/M (Will Sowerbutts, 2014-07-02)\n");

    // test();

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

    // TODO: WRS -- what is the real reason for requiring page alignment? We
    // could easily modify relocate_cpm() to do full 16-bit relocation. CP/M
    // does not appear to require it itself. Asked the N8VEM mailing list if
    // this is an actual requirement.
    //
    // We require CP/M to be page aligned. It is not safe to call
    // allocate_memory() again after we do this.
    target = (unsigned char*)(((unsigned int)target) & 0xFF00);
    printf("\nLoading Residual CP/M at 0x%04X ...", target);
    relocate_cpm(target);
    printf(" booting.\n");

    // boot the residual CP/M system
    boot_cpm(target+BOOT_VECTOR_OFFSET);
}
