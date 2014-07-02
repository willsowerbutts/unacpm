#ifndef __BIOS_DOT_H__
#define __BIOS_DOT_H__

union regs {
    struct {
        unsigned char C, B, E, D, L, H, F, A;
    } b;
    struct {
        unsigned int BC, DE, HL, AF;
    } w;
};

extern union regs reg_in, reg_out; // located in init.c
void bios_call(union regs *regout, union regs *regin);
void boot_cpm(void *target);

#define UNABIOS_STUB_START            0xFF00 // UNA BIOS stub start
#define UNABIOS_STUB_ENTRY            0xFF80 // main UNA entry vector
#define UNABIOS_CALL                  0x08   // entry vector
#define UNABIOS_GETINFO               0xFA   // C regsister (subfunction in B)
#define UNABIOS_GET_SIGNATURE         0x00   //   B register (GETINFO subfunction)
#define UNABIOS_GET_STRING_SHORT      0x01   //   B register (GETINFO subfunction)
#define UNABIOS_GET_STRING_LONG       0x02   //   B register (GETINFO subfunction)
#define UNABIOS_GET_PAGE_NUMBERS      0x03   //   B register (GETINFO subfunction)
#define UNABIOS_GET_VERSION           0x04   //   B register (GETINFO subfunction)
#define UNABIOS_BANKEDMEM             0xFB   // C register (subfunction in B)
#define UNABIOS_BANK_GET              0x00   //   B register (BANKEDMEM subfunction)
#define UNABIOS_BANK_SET              0x01   //   B register (BANKEDMEM subfunction)
#define UNABIOS_MALLOC                0xF7   // C register (byte count in DE)
#define UNABIOS_INPUT_READ            0x11   // C register (unit number in B)
#define UNABIOS_OUTPUT_WRITE          0x12   // C register (unit number in B)
#define UNABIOS_INPUT_STATUS          0x13   // C register (unit number in B)
#define UNABIOS_OUTPUT_STATUS         0x14   // C register (unit number in B)
#define UNABIOS_OUTPUT_WRITE_STRING   0x15   // C register (unit number in B)
#define UNABIOS_BLOCK_SETLBA          0x41   // C register (unit number in B, 28-bit LBA in DEHL)
#define UNABIOS_BLOCK_READ            0x42   // C register (unit number in B, buffer address in DE, sector count in L)
#define UNABIOS_BLOCK_WRITE           0x43   // C register (unit number in B, buffer address in DE, sector count in L)
#define UNABIOS_BLOCK_GET_CAPACITY    0x45   // C register (unit number in B, DE=0 or pointer to 512-byte buffer)
#define UNABIOS_BLOCK_GET_TYPE        0x48   // C register (unit number in B)

#endif
