UNABIOS_STUB_ENTRY          = 0xFFFD    ; main UNA entry vector
UNABIOS_CALL                = 0x08      ; entry vector
UNABIOS_GETINFO             = 0xFA      ; C regsister (subfunction in B)
UNABIOS_GET_SIGNATURE       = 0x00      ;   B register (GETINFO subfunction)
UNABIOS_GET_STRING_SHORT    = 0x01      ;   B register (GETINFO subfunction)
UNABIOS_GET_STRING_LONG     = 0x02      ;   B register (GETINFO subfunction)
UNABIOS_GET_PAGE_NUMBERS    = 0x03      ;   B register (GETINFO subfunction)
UNABIOS_GET_VERSION         = 0x04      ;   B register (GETINFO subfunction)
UNABIOS_GET_USER_PAGES      = 0x05      ;   B register (GETINFO subfunction)
UNABIOS_BANKEDMEM           = 0xFB      ; C register (subfunction in B)
UNABIOS_BANK_GET            = 0x00      ;   B register (BANKEDMEM subfunction)
UNABIOS_BANK_SET            = 0x01      ;   B register (BANKEDMEM subfunction)
UNABIOS_MALLOC              = 0xF7      ; C register (byte count in DE)
UNABIOS_INPUT_READ          = 0x11      ; C register (unit number in B)
UNABIOS_OUTPUT_WRITE        = 0x12      ; C register (unit number in B)
UNABIOS_INPUT_STATUS        = 0x13      ; C register (unit number in B)
UNABIOS_OUTPUT_STATUS       = 0x14      ; C register (unit number in B)
UNABIOS_OUTPUT_WRITE_STRING = 0x15      ; C register (unit number in B)
UNABIOS_BLOCK_SETLBA        = 0x41      ; C register (unit number in B, 28-bit LBA in DEHL)
UNABIOS_BLOCK_READ          = 0x42      ; C register (unit number in B, buffer address in DE, sector count in L)
UNABIOS_BLOCK_WRITE         = 0x43      ; C register (unit number in B, buffer address in DE, sector count in L)
UNABIOS_BLOCK_GET_CAPACITY  = 0x45      ; C register (unit number in B, DE=0 or pointer to 512-byte buffer)
UNABIOS_BLOCK_GET_TYPE      = 0x48      ; C register (unit number in B)
UNABIOS_BOOTHISTORY         = 0xFC      ; C register (subfunction in B)
UNABIOS_BOOT_GET            = 0x00      ;   B register (BOOTHISTORY subfunction)
UNABIOS_BOOT_SET            = 0x01      ;   B register (BOOTHISTORY subfunction)
UNABIOS_GET_HMA             = 0xF1      ; C register (subfunction in B)

BIOS_IDENTITY_POINTER       = 0xFFFE    ; last two bytes of RAM point to ID bytes

; UNA ID bytes: '"push iy" as the initial instruction is cast in concrete as far as I'm concerned.' -- JC
BIOS_ID_UNA_BYTE0           = 0xFD
BIOS_ID_UNA_BYTE1           = 0xE5
