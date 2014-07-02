#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include "units.h"
#include "bios.h"

unit_info_t unit_info[MAXUNITS];

char unit_name_buffer[8];
char unit_size_buffer[10];
char *sector_buffer = (char*)0x8000; // any 512-byte region in memory we can scribble on

bool check_bios_call( union regs *regout, union regs *regin ) // returns true on error
{
    bios_call(regout, regin);
    if(regout->b.C){
        printf("UNA BIOS ERROR 0x%02X\n", regout->b.C);
        return true;
    }
    return false;
}

const char *media_name(media_t type)
{
    switch(type){
        case MEDIA_RAM: return "RAM";
        case MEDIA_ROM: return "ROM";
        case MEDIA_HD:  return "HD";
        default:        return "UNKNOWN";
    }
}

char *unit_size(unsigned char num)
{
    unsigned long size;
    unsigned char shift = 0;
    char suffix = ' ';

    // we want to divide by 2 (sectors -> KB) and multiply by 10 (for our 1 decimal place)
    size = unit_info[num].sectors * 5;

    if(size > (1024L*1024L*10L)){ // GB?
        shift = 20;
        suffix = 'G';
    }else if(size > 1024*10){ // MB?
        shift = 10;
        suffix = 'M';
    }else{ // KB
        shift = 0;
        suffix = 'K';
    }
    size = size >> shift;
    sprintf(unit_size_buffer, "%ld.%d%cB", size/10, (int)(size%10), suffix);

    return unit_size_buffer;
}

char *unit_name(unsigned char num)
{
    sprintf(unit_name_buffer, "%s%d", media_name(unit_info[num].media), unit_info[num].index);
    return unit_name_buffer;
}

bool media_sliced(media_t type)
{
    switch(type){
        case MEDIA_HD:  return true;
        default:        return false;
    }
}

media_t driver_id_to_media(unsigned char id, unsigned char flags)
{
    switch(id){
        case 0x40:
            if(flags & 0x04)
                return MEDIA_ROM;
            else
                return MEDIA_RAM;
        case 0x41:
        case 0x42:
        case 0x43:
        case 0x44:
            return MEDIA_HD;
        default:
            return MEDIA_OTHER;
    }
}

const char *driver_name(unsigned char id)
{
    switch(id){
        case 0x40: return "Memory";
        case 0x41: return "Dual-IDE";
        case 0x42: return "PP-IDE";
        case 0x43: return "CSIO-SD";
        case 0x44: return "Dual-SD";
        default:   return "Unknown";
    }
}

void unit_parse_mbr(unsigned char num)
{
    unsigned char p;
    unsigned long lba_first, lba_count;
    master_boot_record_t *mbr = (master_boot_record_t*)sector_buffer;
    partition_table_entry_t *part = &mbr->partition[0];

    lba_first = 0;
    lba_count = unit_info[num].sectors;

    // read first sector from unit
    reg_in.b.B = num;
    reg_in.b.C = UNABIOS_BLOCK_SETLBA;
    reg_in.w.DE = 0;
    reg_in.w.HL = 0;
    if(check_bios_call(&reg_out, &reg_in))
        return;

    reg_in.b.B = num;
    reg_in.b.C = UNABIOS_BLOCK_READ;
    reg_in.b.L = 1; // single sector
    reg_in.w.DE = (unsigned int)mbr;
    if(check_bios_call(&reg_out, &reg_in))
        return;

    if(mbr->signature == 0xaa55){
        for(p=0; p<MBR_ENTRY_COUNT; p++){
            if(part->type == 0x32){ // bingo
                // printf("[found 0x32]");
                unit_info[num].flags |= UNIT_FLAG_CPM_PARTITION;
                lba_first = part->lba_first;
                lba_count = part->lba_count;
                break; // look no further
            }else if(part->type == 0x05 || part->type == 0x0F){ // CHS/LBA extended partition?
                // ignore these to allow them to be used as "protective partition" purposes
            }else if(part->type){ // any other non-empty foreign partition?
                // first sector of this partition sets a ceiling on what we can use for CP/M slices
                if(part->lba_first < lba_count){
                    unit_info[num].flags |= UNIT_FLAG_FOREIGN_PARTITION;
                    lba_count = part->lba_first;
                }
            }
            part++; // next partition
        }
    }

    // record first usable sector
    unit_info[num].lba_first = lba_first;

    // compute number of slices
    lba_count = lba_count / SECTORS_PER_SLICE;
    
    // limit to maximum slices we can address
    if(lba_count > 0xFFFF)
        lba_count = 0xFFFF;

    unit_info[num].slice_count = lba_count;
}

void init_units(void)
{
    media_t m;
    unsigned char driver;
    unsigned char unit, i;
    unsigned char unit_count;

    memset(unit_info, 0, sizeof(unit_info));

    // get unit count
    reg_in.b.B = 0;
    reg_in.b.C = UNABIOS_BLOCK_GET_TYPE;
    check_bios_call(&reg_out, &reg_in);
    unit_count = reg_out.b.L; // total units in system

    // confirm internal limit is not exceeded
    if(unit_count > MAXUNITS){
        printf("WARNING: UNA reports %d units, MAXUNITS is %d.\n", unit_count, MAXUNITS);
        unit_count = MAXUNITS;
    }

    printf("\nDisk  Driver   Capacity  Slices   Start LBA\n");

    for(unit=0; unit<unit_count; unit++){
        // set flags
        unit_info[unit].flags = 0;

        // get type information
        reg_in.b.B = unit;
        reg_in.b.C = UNABIOS_BLOCK_GET_TYPE;
        check_bios_call(&reg_out, &reg_in);
        // printf("DE=%04x HL=%04x ", reg_out.w.DE, reg_out.w.HL);

        // media type
        driver = reg_out.b.D;
        m = driver_id_to_media(driver, reg_out.b.H);
        unit_info[unit].media = m;

        // compute index
        unit_info[unit].index = 0;
        for(i=0; i<unit; i++)
            if(unit_info[i].media == m)
                unit_info[unit].index++;

        // get capacity
        reg_in.b.C = UNABIOS_BLOCK_GET_CAPACITY;
        reg_in.w.DE = 0;
        check_bios_call(&reg_out, &reg_in);
        // printf("B=%02x ", reg_out.b.B);
        unit_info[unit].sectors = (((unsigned long)reg_out.w.DE) << 16) | (reg_out.w.HL);

        // sliced?
        if(media_sliced(m)){
            unit_parse_mbr(unit);
        }else{
            unit_info[unit].lba_first = 0;
            unit_info[unit].slice_count = 1;
        }

        printf("%-5s %-8s %8s  %6d  0x%08lX\n", unit_name(unit), driver_name(driver), unit_size(unit), 
                unit_info[unit].slice_count, unit_info[unit].lba_first);
    }

    // mark other units as absent
    for(; unit<unit_count; unit++)
        unit_info[unit].media = MEDIA_NONE;
}
