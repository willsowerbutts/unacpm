#ifndef __UNITS_DOT_H__
#define __UNITS_DOT_H__

#include <stdbool.h>

typedef enum { MEDIA_NONE, MEDIA_RAM, MEDIA_ROM, MEDIA_HD, MEDIA_OTHER } media_t;

#define SECTORS_PER_SLICE 0x4100     // 8.125MB per CP/M slice

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

#define UNIT_FLAG_CPM_PARTITION       1
#define UNIT_FLAG_FOREIGN_PARTITION   2

typedef struct {
    media_t media;              // media type
    unsigned char flags;        // UNIT_FLAG_*
    unsigned char index;        // media index (Nth device with this type)
    unsigned long sectors;      // device sector count
    unsigned long lba_first;    // address of first usable sector
    unsigned int slice_count;   // number of usable slices on device (only for sliced media types)
} unit_info_t;

#define MAXUNITS 10
extern unit_info_t unit_info[MAXUNITS];

void init_units(void);
char *unit_name(unsigned char num);

#endif
