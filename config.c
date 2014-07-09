#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "drives.h"
#include "units.h"
#include "memory.h"
#include "config.h"

config_block_t config_block;
extern bool update_saved_config;

bool empty_string(const char *p)
{
    while(*p){
        if(!isspace(*p))
            return false;
        p++;
    }
    return true;
}

bool parse_option(const char *option)
{
    unsigned char unit;

    if(*option != '/')
        return false;
    option++;

    if(strncmp(option, "SAVE", 4) == 0){
        update_saved_config = true;
        return true;
    }

    if(strncmp(option, "CONFDISK", 8) == 0 && (option[8] == ':' || option[8] == '=')){
        unit = unit_from_name(option + 9);
        if(unit == NO_UNIT){
            print_to_space(option+9);
            printf(": Cannot find disk\n");
            return false;
        }
        if(!(media_sliced(unit_info[unit].media) && unit_info[unit].slice_count)){
            print_to_space(option+9);
            printf(": Configuration can be stored only on sliced disks\n");
            return false;
        }
        persist->config_unit = unit;
        printf("Configuration disk set to %s\n", unit_name(unit));
        return true;
    }

    if(strncmp(option, "CONFERASE", 9) == 0 && (option[9] == ':' || option[9] == '=')){
        unit = unit_from_name(option + 10);
        if(unit == NO_UNIT){
            print_to_space(option+10);
            printf(": Cannot find disk\n");
            return false;
        }
        if(!(media_sliced(unit_info[unit].media) && unit_info[unit].slice_count)){
            print_to_space(option+10);
            printf(": Configuration can be stored only on sliced disks\n");
            return false;
        }
        printf("Erasing saved configuration on %s\n", unit_name(unit));
        memset(&config_block, 0xE5, sizeof(config_block));
        return unit_save_configuration(unit, &config_block);
    }

    print_to_space(option-1);
    printf(": Cannot parse command line option\n");

    return false;

}

bool config_load_from_string(const char *string)
{
    bool okay;
    const char *p;

    p = string;
    okay = true;

    while(*p){
        while(*p && isspace(*p))
            p++;

        if(*p){
            if(*p == '/'){ // option?
                okay = parse_option(p) && okay;
            }else{
                okay = drives_extend_mapping(p) && okay;
            }
        }

        while(*p && !isspace(*p))
            p++;
    }

    return okay;
}

bool config_load_from_unit(unsigned char num)
{
    config_block_t *cfg;

    cfg = unit_load_configuration(num);
    if(cfg == NULL)
        return false;

    if(cfg->version != CONFIG_VERSION){
        printf("Unsupported configuration version 0x%02x on unit %d\n", cfg->version, num);
        return false;
    }

    printf("Loading CP/M drive configuration from %s\n", unit_name(num));
    return config_load_from_string(cfg->configuration);
}

bool config_save_to_unit(unsigned char num)
{
    char *p;

    memset(&config_block, 0, sizeof(config_block));
    config_block.signature = CONFIG_SIGNATURE;
    config_block.version = CONFIG_VERSION;
    p = config_block.configuration;

    drives_mapping_to_string(config_block.configuration, CONFIG_STRING_LEN);

    printf("Saving CP/M drive configuration to %s\n", unit_name(num));
    return unit_save_configuration(num, &config_block);
}

const unsigned char config_flags_preferences[] = {
    UNIT_FLAG_CONFIG_PRESENT | UNIT_FLAG_BOOTED,            // prefer the boot unit, if it has a config block
    UNIT_FLAG_CONFIG_PRESENT | UNIT_FLAG_CPM_PARTITION,     // or a dedicated CP/M partition with a config block
    UNIT_FLAG_CONFIG_PRESENT,                               // or any unit with config present
//  UNIT_FLAG_CPM_PARTITION,                                // or any unit with a dedicated CP/M partition (?)
    0                                                       // just give up, then.
};

void find_configuration_unit(void)
{
    const unsigned char *p;
    if(persist->config_unit != NO_UNIT && persist->config_unit < MAXUNITS && 
            (unit_info[persist->config_unit].flags & UNIT_FLAG_CONFIG_PRESENT)){
        return; // nothing further to do
    }

    // ah, we will have to go searching
    p = config_flags_preferences;
    while(persist->config_unit == NO_UNIT && *p){
        persist->config_unit = find_unit_with_flags(*p);
        p++;
    }

    return;
}

