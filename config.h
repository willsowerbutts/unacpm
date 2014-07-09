#ifndef __CONFIG_DOT_H__
#define __CONFIG_DOT_H__

#include <stdbool.h>

bool empty_string(const char *string);

void find_configuration_unit(void);
bool config_load_from_string(const char *string);
bool config_load_from_unit(unsigned char num);
bool config_save_to_unit(unsigned char num);

#define CONFIG_SIGNATURE 0x05CA
#define CONFIG_VERSION   0x01
#define CONFIG_STRING_LEN 100
typedef struct {
    unsigned int signature;
    unsigned char version;
    char __reserved1[5];            // initialise to zero
    char configuration[CONFIG_STRING_LEN];
    char __reserved2[20];           // initialise to zero
} config_block_t;

#endif
