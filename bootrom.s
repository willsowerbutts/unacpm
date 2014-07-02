; 2014-07-02  Will Sowerbutts <will@sowerbutts.com>

        .module bootrom

        .globl init

; define the order of our areas
        .area _CODE
        .area _TPA
        .area _HOME
        .area _INITIALIZER
        .area _GSINIT
        .area _GSFINAL
        .area _DATA
        .area _INITIALIZED
        .area _BSEG
        .area _STACK
        .area _BSS
        .area _HEAP

UNABIOS_STUB_START          = 0xFF00    ; UNA BIOS stub start
UNABIOS_STUB_ENTRY          = 0xFF80    ; main UNA entry vector
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

; memory values in RAM during bootstrap
; we can use 0x8000 -- 0x803F which is the vector area in ROM, unused in the RAM copy
copyaddr                    = 0x8000    ; 1 byte

; buffer
bouncebuffer                = 0x9000
bouncesize                  = 0x2000    ; must be a factor of 0x8000

        .area _CODE
zero:
        ; entry is at 0x0000, executing from ROM
        jp rom_bootstrap                ; jump over vectors
        halt                            ; fill space until the RST 8 vector with halt instructions
        halt
        halt
        halt
        halt
        jp UNABIOS_STUB_ENTRY           ; UNA RST 8 entry vector
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        halt
        ; we are now at address 0x40
rom_bootstrap:
        ld sp, #UNABIOS_STUB_START      ; put stack underneath BIOS stub

        ; copy ourselves into top half of RAM
        ld de, #0x8000                  ; to RAM
        ld hl, #0x0000                  ; from ROM
        ld bc, #0x100                   ; copy entire bootstrap
        ldir

; ----------------------------------------------------------------------------------------------------
; all jumps after here must be to the RAM copy of code, at 0x8000 plus the assembled address (in ROM)
; ----------------------------------------------------------------------------------------------------

        jp rom_continue+0x8000 ; jump to copy of next instruction, in RAM
rom_continue:
        xor a                           ; start copying at 0x0000
        ld (copyaddr), a

rom_copyloop:
        ld de, #bouncebuffer            ; to high memory bounce buffer, above us in RAM
        ld a, (copyaddr)
        ld h, a                         ; from (copyaddr << 8) in ROM.
        ld l, #0
        ld bc, #bouncesize
        ldir                            ; copy

        ; get the page number for the user memory bank
        ld bc, #(UNABIOS_GET_USER_PAGES << 8 | UNABIOS_GETINFO)
        rst #UNABIOS_CALL               ; can use this; we place the vector in ROM
        ; returns EXEC_PAGE value in DE
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        rst #UNABIOS_CALL               ; map in EXEC_PAGE
        push de                         ; save ROM page number

        ld a, (copyaddr)                ; to low RAM
        ld d, a
        ld e, #0
        ld hl, #bouncebuffer            ; from high memory bounce buffer, above us
        ld bc, #bouncesize
        ldir                            ; copy

        ld a, d
        ld (copyaddr), a                ; update copyaddr
        cp #0x80                        ; done at 0x8000?
        jp z, rom_copydone+0x8000

        pop de                          ; recover ROM page number
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        rst #UNABIOS_CALL               ; map in ROM -- on the first cycle we install the required vector
        jp rom_copyloop+0x8000

rom_copydone:
        pop de                          ; remove ROM page number from stack

        ; overwrite bootstrap code in low memory with halts (we are executing in the high memory copy)
        ld hl, #0x0030                  ; we place a HALT here already
        ld de, #0x0000
        ld bc, #0x0003                  ; overwrite the 3-byte boot vector
        ldir

        ld hl, #0x0030                  ; we place a HALT here already
        ld de, #0x0031
        ld bc, #0x00CF                  ; to 0x0100
        ldir

        xor a                           ; wipe out the CP/M command buffer
        ld (0x0080), a                  ; char count
        ld (0x0081), a                  ; null terminated string

        ; install a signature (in the same location RomWBW uses)
        ld hl, #0x05B1
        ld (0x0040), hl

        ; we leave user memory mapped in and do not refer to ROM again
        jp init

bootrom_code_len = (. - zero)
.ifgt (bootrom_code_len - 0x100) ; did we grow too large?
; cause an error (.msg, .error not yet supported by sdas which itself is an error)
.msg "Boot ROM code/data is too large"
.error 1
.endif
; make space so the "init" symbol in runtime0.s is at 0x100
        .ds 0x100 - (. - zero)          ; space until the CP/M load vector
