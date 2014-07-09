#ifndef __DRIVES_DOT_H__
#define __DRIVES_DOT_H__

#include <stdbool.h>

void init_drives(void);
bool drives_extend_mapping(const char *device);
void drives_mapping_to_string(char *buffer, unsigned char maxlen);
void drives_default_mapping(void);
void prepare_drives(void);
void print_to_space(const char *p);
unsigned char drives_count_valid(void);

typedef struct {
    unsigned char unit;
    unsigned int slice;
} drive_t;

typedef struct {
    unsigned int  sectors_per_track;
    unsigned char block_shift_factor;
    unsigned char block_mask;
    unsigned char extent_mask;
    unsigned int  block_count; // -1
    unsigned int  dirent_count; // -1
    unsigned int  dirent_alloc_vector;
    unsigned int  check_vector_size;
    unsigned int  system_tracks;
} dpb_t; // must be 15 bytes

typedef struct {
    unsigned int xlt;
    unsigned int bdos_scratchpad[3];
    void *dirbuf;
    dpb_t *dpb;
    void *checksum_vector;
    void *allocation_vector;
} dph_t; // must be 16 bytes

typedef struct {
    unsigned char unit;
    dph_t *dph;
    unsigned long lba_first;
    char __spare; // pad to power of 2
} drive_map_t; // 8 bytes

#endif
