#include <stdio.h>
#include <stdbool.h>
#include "cpmimage.h"

unsigned int cksum;
const unsigned char *dataptr;
unsigned char databit;
#define TOPBIT 128

bool relocate_nextbit(void);
unsigned char relocate_nextbyte(void);

/*
 * relocate2.s contains faster assembler implementations of these two functions
 *
bool relocate_nextbit(void)
{
    bool r;

    r = *dataptr & databit;
    databit = databit >> 1;
    if(databit == 0){
        databit=TOPBIT;
        dataptr++;
    }

    return r;
}

unsigned char relocate_nextbyte(void)
{
    unsigned char out = 0;
    unsigned char bits = 8;

    // printf("\n");

    while(1){
        if(relocate_nextbit())
            out |= 1;
        if(--bits == 0){
            cksum += out;
            return out;
        }
        out = out << 1;
    }
}
*/

unsigned int relocate_read_int(unsigned char bits)
{
    unsigned int out = 0;

    while(1){
        if(relocate_nextbit())
            out |= 1;
        if(--bits == 0)
            return out;
        out = out << 1;
    }
}

bool relocate_cpm(unsigned char *dest)
{
    unsigned char *target;
    unsigned int length;
    unsigned int reloc_offset;
    unsigned int *r;
    bool first;

    reloc_offset = (unsigned int)dest;
    target = dest;
    dataptr = cpm_image_data;
    databit = TOPBIT;
    cksum = 0;
    first = true;

    while(1){
        length = relocate_read_int(2);
        if(!length){
            length = relocate_read_int(4);
            if(!length){
                length = relocate_read_int(10);
                if(!length){
                    if((unsigned int)(target - dest) != cpm_image_length){
                        printf("length mismatch\n");
                        return false;
                    }
                    if(cksum != cpm_image_cksum){
                        printf("checksum mismatch\n");
                        return false;
                    }
                    // seems OK
                    return true;
                }else{
                    length = length + 19;
                }
            }else{
                length = length + 4;
            }
        }else{
            length = length + 1;
        }

        if(first){
            // do not relocate the first run
            first = false;
        }else{
            // we wrote the low byte in the previous pass
            // now we write the high byte;
            *(target++) = relocate_nextbyte();
            // the we relocate the value just written;
            r = (unsigned int*)(target - 2);
            *r += reloc_offset;
            length--;
        }

        while(length--)
            *(target++) = relocate_nextbyte();
    }
}
