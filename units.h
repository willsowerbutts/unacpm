#ifndef __UNITS_DOT_H__
#define __UNITS_DOT_H__

#include <stdbool.h>
#include "config.h"

typedef enum { 
    MEDIA_NONE=0, 
    MEDIA_RAM, 
    MEDIA_ROM, 
    MEDIA_IDE, 
    MEDIA_SD,
    MEDIA_DSK, 
    MEDIA_OTHER
        // also update media_names[] in units.c when adding new entries
} media_t;

#define SECTORS_PER_SLICE    0x4100     // 8.125MB per CP/M slice
#define RAM_DISK_MAX_SECTORS 8192       // 4MB RAM disk is as large as we can handle with 2KB blocks

typedef struct {
    unsigned char status;
    unsigned char chs_first[3];
    unsigned char type;
    unsigned char chs_last[3];
    unsigned long lba_first;
    unsigned long lba_count;
} partition_table_entry_t;

#define MBR_ENTRY_COUNT 4
typedef struct {
    unsigned char bootcode[446];
    partition_table_entry_t partition[MBR_ENTRY_COUNT];
    unsigned int signature;
} master_boot_record_t;

#define UNIT_FLAG_MBR_PRESENT         1     // unit contains a valid MBR
#define UNIT_FLAG_CPM_PARTITION       2     // unit has a CP/M partition (type 0x32)
#define UNIT_FLAG_FOREIGN_PARTITION   4     // unit has one or more foreign partitions
#define UNIT_FLAG_IGNORED_PARTITION   8     // unit has one or more ignored ("protective") partitions
#define UNIT_FLAG_CONFIG_PRESENT      16    // unit contains an UNA CP/M config block in CP/M slice 0
#define UNIT_FLAG_BOOTED              32    // unit was the boot drive
#define UNIT_FLAG__UNUSED             64    // (free)
#define UNIT_FLAG_FORMATTED           128   // this records an action we took rather than a property of the media

typedef struct {
    media_t media;              // media type
    unsigned char flags;        // UNIT_FLAG_*
    unsigned char index;        // media index (Nth device with this type)
    unsigned long sectors;      // device sector count
    unsigned long lba_first;    // address of first usable sector
    unsigned int slice_count;   // number of usable slices on device (only for sliced media types)
} unit_info_t;

#define NO_UNIT 0xFF
#define MAXUNITS 10
extern unit_info_t unit_info[MAXUNITS];

void init_units(void);
char *unit_name(unsigned char num);
unsigned char unit_from_name(const char *name);
bool media_sliced(media_t type);
config_block_t *unit_load_configuration(unsigned char num);
bool unit_save_configuration(unsigned char num, config_block_t *cfg);
unsigned char find_unit_with_flags(unsigned char flags);

#endif
