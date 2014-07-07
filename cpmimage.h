#ifndef __CPMIMAGE_DOT_H__
#define __CPMIMAGE_DOT_H__

extern const unsigned int cpm_image_length;
extern const unsigned int cpm_image_cksum;
extern const unsigned char cpm_image_data[];
extern const unsigned char cpm_image_encoding[];
extern const unsigned char cpm_image_offsets[];

#define BOOT_VECTOR_OFFSET 0x1600

#endif
