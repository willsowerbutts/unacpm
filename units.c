#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <stdbool.h>
#include "units.h"
#include "bios.h"
#include "config.h"

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

const char *media_names[] = {
    "(none)",
    "RAM",
    "ROM",
    "IDE",
    "SD",
    "DSK",
    "(unknown)",
};

const char *media_name(media_t type)
{
    if(type < (sizeof(media_names) / sizeof(const char*)))
        return media_names[type];
    return media_names[0];
}

unsigned char unit_from_name(const char *name)
{
    int namelen;
    media_t m;
    unsigned char i, n;

    for(m=0; m < (sizeof(media_names) / sizeof(const char*)); m++){
        namelen = strlen(media_names[m]);
        if(strncmp(media_names[m], name, namelen) == 0 && isdigit(name[namelen])){
            i = atoi(&name[namelen]);
            for(n=0; n<MAXUNITS; n++)
                if(unit_info[n].media == m && unit_info[n].index == i)
                    return n;
        }
    }

    return NO_UNIT;
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
        case MEDIA_IDE:
        case MEDIA_SD:
        case MEDIA_DSK:
            return true;
        default:        
            return false;
    }
}

media_t driver_id_to_media(unsigned char id, unsigned char flags)
{
    switch(id){
        case 0x40:
            if(flags & 0x80)
                return MEDIA_RAM;
            else
                return MEDIA_ROM;
        case 0x41:
        case 0x42:
            return MEDIA_IDE;
        case 0x43:
        case 0x44:
            return MEDIA_SD;
        default:
            return MEDIA_DSK;
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

bool xfer_sector(unsigned char num, unsigned char lba, unsigned char disk_op)
{
    reg_in.b.B = num;
    reg_in.b.C = UNABIOS_BLOCK_SETLBA;
    reg_in.w.DE = 0;
    reg_in.w.HL = lba;
    if(check_bios_call(&reg_out, &reg_in)){
        unit_info[num].sectors = 0;
        return false;
    }

    reg_in.b.B = num;
    reg_in.b.C = disk_op;
    reg_in.b.L = 1; // single sector
    reg_in.w.DE = (unsigned int)sector_buffer;
    if(check_bios_call(&reg_out, &reg_in)){
        unit_info[num].sectors = 0;
        return false;
    }

    return true;
}

void ram_disk_consider_format(unsigned char num)
{
    unsigned char sector, entry, *status, disk_op;
    unsigned int valid;

    // read the status byte of each CP/M directory entry, count 
    // how many valid/invalid entries we find.
    valid = 0;
    disk_op = UNABIOS_BLOCK_READ;
    while(true){
        for(sector=0; sector<16; sector++){ // 256-entry directory is the first 16 sectors
            // read/write sector from unit
            if(!xfer_sector(num, sector, disk_op))
                return;

            // check the status byte of each entry
            status = sector_buffer;
            for(entry=0; entry<16; entry++){
                if(*status == 0xE5 || *status < 34) // see http://www.cpm8680.com/cpmtools/cpm.htm
                    valid++;
                status += 32; // next directory entry
            }
        }
        if(disk_op == UNABIOS_BLOCK_WRITE){ // did we finish the second pass?
            unit_info[num].flags |= UNIT_FLAG_FORMATTED;
            return;
        }
        if(valid >= 230)  // first pass -- more than 90% were valid?
            return;       // no need to format
        // first pass -- set up to format
        disk_op = UNABIOS_BLOCK_WRITE;
        memset(sector_buffer, 0xe5, 512);
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

    // read first sector from unit into buffer
    if(!xfer_sector(num, 0, UNABIOS_BLOCK_READ))
        return;

    if(mbr->signature == 0xaa55){
        unit_info[num].flags |= UNIT_FLAG_MBR_PRESENT;
        for(p=0; p<MBR_ENTRY_COUNT; p++){
            if(part->type == 0x32){ // bingo
                unit_info[num].flags |= UNIT_FLAG_CPM_PARTITION;
                lba_first = part->lba_first;
                lba_count = part->lba_count;
                break; // look no further
            }else if(part->type == 0x05 || part->type == 0x0F){ // CHS/LBA extended partition?
                unit_info[num].flags |= UNIT_FLAG_IGNORED_PARTITION;
                // ignore these to allow them to be used as "protective partition" purposes
            }else if(part->type == 0x52 && part->lba_count == 0x4000 && (part->lba_first % 0x4100) == 0x100){ // CP/M-68 data partition
                // ignore any CP/M-68 data partition that overlays a RomWBW slice    JRC 2015-05-12
                unit_info[num].flags |= UNIT_FLAG_IGNORED_PARTITION;
                // ignore these to allow them to be used as "protective partition" purposes
            }else if(part->type){ // any other non-empty foreign partition?
                unit_info[num].flags |= UNIT_FLAG_FOREIGN_PARTITION;
                // first sector of this partition sets a ceiling on what we can use for CP/M slices
                // only apply this if we've not found a CP/M partition
                if(!(unit_info[num].flags & UNIT_FLAG_CPM_PARTITION)){
                    if(part->lba_first < lba_count){
                        lba_count = part->lba_first;
                    }
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

config_block_t *unit_load_configuration(unsigned char num)
{
    config_block_t *config = (config_block_t*)sector_buffer;

    if(num < MAXUNITS && media_sliced(unit_info[num].media) && unit_info[num].slice_count){
        // load second 512-byte sector from the system track of this unit's first slice
        xfer_sector(num, 1, UNABIOS_BLOCK_READ);
        if(config->signature == CONFIG_SIGNATURE)
            return config;
    }

    return NULL;
}

bool unit_save_configuration(unsigned char num, config_block_t *cfg)
{
    config_block_t *target = (config_block_t*)sector_buffer;

    if(!(num < MAXUNITS && media_sliced(unit_info[num].media) && unit_info[num].slice_count))
        return false;

    // load second 512-byte sector from the system track of this unit's first slice
    if(!xfer_sector(num, 1, UNABIOS_BLOCK_READ))
        return false;

    // merge in the config block
    memcpy(target, cfg, sizeof(config_block_t));

    // write updated sector back to disk
    if(!xfer_sector(num, 1, UNABIOS_BLOCK_WRITE))
        return false;

    return true;
}

unsigned char find_unit_with_flags(unsigned char flags)
{
    unsigned char i;

    for(i=0; i<MAXUNITS; i++)
        if((unit_info[i].flags & flags) == flags) // all flags must be set
            return i;

    return NO_UNIT;
}

void init_units(void)
{
    media_t m;
    unsigned char driver, unaflags;
    unsigned char unit, i;
    unsigned char unit_count;
    unit_info_t *u;

    memset(unit_info, 0, sizeof(unit_info));

    // flag the unit we booted from
    reg_in.b.C = UNABIOS_BOOTHISTORY;
    reg_in.b.B = UNABIOS_BOOT_GET;
    if(!check_bios_call(&reg_out, &reg_in)){
        if(reg_out.b.L < MAXUNITS)
            unit_info[reg_out.b.L].flags |= UNIT_FLAG_BOOTED;
    }

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

    printf("\nUnit Disk  Driver   Capacity  Slices   Start LBA  Flags\n");

    for(unit=0; unit<unit_count; unit++){
        u = &unit_info[unit];
        unaflags = 0;
        driver = 0;

        // get type information
        reg_in.b.B = unit;
        reg_in.b.C = UNABIOS_BLOCK_GET_TYPE;
        if(!check_bios_call(&reg_out, &reg_in))
            driver = reg_out.b.D;

        // get capacity
        reg_in.b.C = UNABIOS_BLOCK_GET_CAPACITY;
        reg_in.w.DE = 0;
        if(!check_bios_call(&reg_out, &reg_in)){
            u->sectors = (((unsigned long)reg_out.w.DE) << 16) | (reg_out.w.HL);
            unaflags = reg_out.b.B;
        }

        // media type
        m = driver_id_to_media(driver, unaflags);
        u->media = m;

        // compute index
        u->index = 0;
        for(i=0; i<unit; i++)
            if(unit_info[i].media == m)
                u->index++;

        if(m == MEDIA_RAM && u->sectors <= RAM_DISK_MAX_SECTORS)
            ram_disk_consider_format(unit);

        // sliced?
        u->lba_first = 0;
        if(media_sliced(m)){
            if(u->sectors > 1){
                unit_parse_mbr(unit);
                if(u->slice_count)
                    if(unit_load_configuration(unit))
                        u->flags |= UNIT_FLAG_CONFIG_PRESENT;
            }else{
                u->slice_count = 0;
            }
        }else{
            u->slice_count = 1;
        }

        printf("%-4d %-5s %-8s %8s  %6d  0x%08lX  ", 
                unit, unit_name(unit), driver_name(driver), unit_size(unit), 
                u->slice_count, u->lba_first);

        // print flags
        if(u->flags & UNIT_FLAG_MBR_PRESENT)
            printf("MBR ");
        if(u->flags & UNIT_FLAG_CPM_PARTITION)
            printf("CPM ");
        if(u->flags & UNIT_FLAG_FOREIGN_PARTITION)
            printf("FGN ");
        if(u->flags & UNIT_FLAG_IGNORED_PARTITION)
            printf("IGN ");
        if(u->flags & UNIT_FLAG_CONFIG_PRESENT)
            printf("CFG ");
        if(u->flags & UNIT_FLAG_BOOTED)
            printf("BOOT ");
        if(u->flags & UNIT_FLAG_FORMATTED)
            printf("(formatted) ");
        printf("\n");
    }

    // mark other units as absent
    for(; unit<unit_count; unit++)
        unit_info[unit].media = MEDIA_NONE;
}
