#ifndef __MEMORY_DOT_H__
#define __MEMORY_DOT_H__

#include <stdbool.h>
#include "drives.h"

void *allocate_memory(unsigned int size);
void write_persist(unsigned char *target, unsigned int cpm_image_length);
bool init_persist(void);

#define PERSIST_SIGNATURE 0x1653
#define PERSIST_VERSION   0x01

// keep this in sync with cpmbios.s (search for "persist_t" at the end)
typedef struct {
    unsigned int signature;         // persist_signature (at address 0xFEFE)
    unsigned char version;          // persist_version
    // data from init to residual (not versioned)
    drive_map_t *drive_map;         // drvmap
    unsigned char drive_count;      // drvcnt
    // data that we persist between sessions (versioned)
    unsigned char config_unit;      // config_unit
    void *ubios_ccp_clone;          // ccpadr
    void *ubios_sector_buffer;      // bufadr
} persist_t;

extern persist_t persist;

#endif
