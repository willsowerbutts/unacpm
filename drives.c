#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <ctype.h>
#include "memory.h"
#include "drives.h"
#include "units.h"

#define MAXDRIVES 16 // CP/M limit is 16.

drive_t drive_info[MAXDRIVES];
void *cpm_dirbuf;

dpb_t *shared_hdd_dpb = NULL;

const dpb_t mem_dpb_template = {
    64,         // unsigned int  sectors_per_track;
    4,          // unsigned char block_shift_factor;
    15,         // unsigned char block_mask;
    1,          // unsigned char extent_mask; // assume block_count >= 256
    0,          // unsigned int  block_count; // -1
    255,        // unsigned int  dirent_count; // -1
    0x00f0,     // unsigned int  dirent_alloc_vector;
    0,          // unsigned int  check_vector_size;
    0           // unsigned int  system_tracks;
};

const dpb_t hdd_dpb_template = {
    64,         // unsigned int  sectors_per_track;
    5,          // unsigned char block_shift_factor;
    31,         // unsigned char block_mask;
    1,          // unsigned char extent_mask;
    2047,       // unsigned int  block_count; // -1
    511,        // unsigned int  dirent_count; // -1
    0x00f0,     // unsigned int  dirent_alloc_vector;
    0,          // unsigned int  check_vector_size;
    16          // unsigned int  system_tracks;
};

// void dump_dpb(dpb_t *dpb)
// {
//     printf("DPB @ 0x%04X:\n", dpb);
//     printf("\tsectors_per_track=%04x\n", dpb->sectors_per_track);
//     printf("\tblock_shift_factor=%02x\n", dpb->block_shift_factor);
//     printf("\tblock_mask=%02x\n", dpb->block_mask);
//     printf("\textent_mask=%02x\n", dpb->extent_mask);
//     printf("\tblock_count=%04x\n", dpb->block_count);
//     printf("\tdirent_count=%04x\n", dpb->dirent_count);
//     printf("\tdirent_alloc_vector=%04x\n", dpb->dirent_alloc_vector);
//     printf("\tcheck_vector_size=%04x\n", dpb->check_vector_size);
//     printf("\tsystem_tracks=%04x\n", dpb->system_tracks);
// }

unsigned char drives_count_valid(void)
{
    unsigned char i;

    for(i=0; i<MAXDRIVES; i++)
        if(drive_info[i].unit == NO_UNIT)
            break;

    return i;
}

void prepare_drives(void)
{
    unsigned char i, valid;
    drive_map_t *drive;
    drive_t *info;
    unit_info_t *unit;
    media_t media;
    dph_t *dph;

    valid = drives_count_valid();
    if(valid == 0){
        drives_default_mapping();
        valid = drives_count_valid();
    }

    cpm_dirbuf = allocate_memory(128); // directory scratch area

    drive = allocate_memory(sizeof(drive_map_t) * valid);
    persist->drive_count = valid;
    persist->drive_map = drive;

    info = drive_info;
    
    for(i=0; i<valid; i++){
        unit = &unit_info[info->unit];
        drive->unit = info->unit;
        drive->lba_first = unit->lba_first +
            (((unsigned long)info->slice) * ((unsigned long)SECTORS_PER_SLICE));
        dph = allocate_memory(sizeof(dph_t));
        drive->dph = dph;
        memset(dph, 0, sizeof(dph_t));
        dph->dirbuf = cpm_dirbuf;

        // prepare the DPH
        media = unit->media;
        if(media_sliced(unit->media)){
            if(!shared_hdd_dpb){
                shared_hdd_dpb = allocate_memory(sizeof(dpb_t));
                memcpy(shared_hdd_dpb, &hdd_dpb_template, sizeof(dpb_t));
            }
            dph->dpb = shared_hdd_dpb;
        }else if(media == MEDIA_RAM || media == MEDIA_ROM){
            dph->dpb = allocate_memory(sizeof(dpb_t));
            memcpy(dph->dpb, &mem_dpb_template, sizeof(dpb_t));
            dph->dpb->block_count = (unit->sectors >> 2) - 1;
            if(dph->dpb->block_count & 0xff00)
                dph->dpb->extent_mask = 0;
        }else{
            printf("Unsupported media type %02x: ", media); // append Drive X: ... info to this output line
        }
        dph->allocation_vector = allocate_memory((dph->dpb->block_count >> 3)+1);

        printf("Drive %c: assigned to %s slice %d\n", 'A' + i, unit_name(info->unit), info->slice);
        // dump_dpb(dph->dpb);
        // next drive
        drive++;
        info++;
    }
}

// fallback mapping: map first slice on every device, in order.
void drives_default_mapping(void)
{
    unsigned char i, d;

    d = 0;
    for(i=0; i<(MAXUNITS < MAXDRIVES ? MAXUNITS : MAXDRIVES); i++){
        if(unit_info[i].media != MEDIA_NONE && unit_info[i].slice_count){
            drive_info[d].unit = i;
            drive_info[d].slice = 0;
            d++;
        }
    }
}

void init_drives(void)
{
    unsigned char i;

    // reset drive mapping
    memset(drive_info, 0, sizeof(drive_info));
    // 0 is a valid unit; fix that.
    for(i=0; i<MAXDRIVES; i++)
        drive_info[i].unit = NO_UNIT;
}

bool drives_load_mapping(int argc, char **argv)
{
    bool errors, fail;
    unsigned char drive, unit, i, d;
    unit_info_t *u;
    char *p;
    unsigned int slice;

    drive = 0;
    errors = false;

    for(i=0; i<argc; i++){
        fail = false;
        unit = unit_from_name(argv[i]);
        if(unit == NO_UNIT){
            printf("\"%s\": Cannot find disk\n", argv[i]);
            fail = true;
        }else{
            u = &unit_info[unit];
            slice = 0;
            p = strchr(argv[i], ':');
            if(!p)
                p = strchr(argv[i], '.'); // alternative
            if(p && media_sliced(u->media)){
                p++;
                slice = atoi(p);
            }
            if(slice >= u->slice_count){
                printf("\"%s\": Slice out of range\n", argv[i]);
                fail = true;
            }else{
                for(d=0; d<drive; d++){
                    if(drive_info[d].unit == unit &&
                            drive_info[d].slice == slice){
                        printf("\"%s\": Already assigned\n", argv[i]);
                        fail = true;
                    }
                }
            }
            if(!fail && drive < MAXDRIVES){
                drive_info[drive].unit = unit;
                drive_info[drive].slice = slice;
                drive++;
            }
        }
        errors = errors || fail;
    }

    return errors;
}
