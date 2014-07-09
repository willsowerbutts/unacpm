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
bootflag                    = 0x8001    ; 1 byte

; buffer
bouncebuffer                = 0x8100
bouncesize                  = 0x2000    ; must be a factor of 0x8000

stackbase                   = 0xa100
stacktop                    = 0xa200

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
cpm_bootstrap:
        ; "warm" boot entry vector in ROM, called by ASSIGN.COM program
        ; command line remains in user memory at 0x80 ... 0x100. We set a flag to preserve it.
        ld a, #0x01 ; warm boot: overwrite RAM from 0x0100 upwards, preserving the CP/M command line
        jr writecopyaddr
rom_bootstrap:
        ; "cold" boot from ROM
        xor a ; cold boot: overwrite all RAM from 0x0000 upwards
writecopyaddr:
        ld (copyaddr), a
        ld (bootflag), a
        ld sp, #stacktop                ; set up stack

        ; copy ourselves into top half of RAM
        ; do not overwrite first few bytes (cold/warm boot flag)
        ld de, #0x8010                  ; to RAM
        ld hl, #0x0010                  ; from ROM
        ld bc, #0x100-0x10              ; copy entire bootstrap
        ldir

; ----------------------------------------------------------------------------------------------------
; all jumps after here must be to the RAM copy of code, at 0x8000 plus the assembled address (in ROM)
; ----------------------------------------------------------------------------------------------------

        jp rom_continue+0x8000 ; jump to copy of next instruction, in RAM
rom_continue:
rom_copyloop:
        ld bc, #bouncesize
        ld de, #bouncebuffer            ; to high memory bounce buffer, above us in RAM
        ld l, #0
        ld a, (copyaddr)
        ld h, a                         ; from (copyaddr << 8) in ROM.
        ldir                            ; copy

        ; get the page number for the user memory bank
        ld bc, #(UNABIOS_GET_USER_PAGES << 8 | UNABIOS_GETINFO)
        rst #UNABIOS_CALL               ; can use this; we place the vector in ROM
        ; returns EXEC_PAGE value in DE
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        rst #UNABIOS_CALL               ; map in EXEC_PAGE
        push de                         ; save ROM page number

        ld hl, #bouncebuffer            ; from high memory bounce buffer, above us
        ld bc, #bouncesize
        ld e, #0
        ld a, (copyaddr)                ; to low RAM
        ld d, a
        cp #1                           ; copying to 0x0100?
        jp nz, gocopy1+0x8000
        dec b                           ; reduce size 0x100 bytes so copyaddr increases just as if we started at zero all along
gocopy1:
        ldir                            ; do the copy

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

        ld a, (bootflag)
        or a
        jp nz, installsig+0x8000        ; warm boot -- skip low memory init

        ; overwrite bootstrap code in low memory with halts (we are executing in the high memory copy)
        ld hl, #0x0030                  ; we place a HALT here already
        ld de, #0x0000
        ld bc, #0x0003                  ; overwrite the 3-byte boot vector
        ldir

        ld hl, #0x0030                  ; we place a HALT here already
        ld de, #0x0031
        ld bc, #0x004F                  ; to 0x0080
        ldir

        xor a                           ; wipe out the CP/M command buffer
        ld (0x0080), a                  ; char count
        ld (0x0081), a                  ; null terminated string

installsig:
        ; install a signature (in the same location RomWBW uses)
        ld hl, #0x05B1
        ld (0x0040), hl

        ; we leave user memory mapped in and do not refer to ROM again
        jp init

memtop = 0x100 - 16 ; leave space for signature

bootrom_code_len = (. - zero)
.ifgt (bootrom_code_len - memtop) ; did we grow too large?
; cause an error (.msg, .error not yet supported by sdas which itself is an error)
.msg "Boot ROM code/data is too large"
.error 1
.endif
; make space so the "init" symbol in runtime0.s is at 0x100
        .ds memtop - (. - zero)          ; space until the CP/M load vector
        .db 0x05,0xCA                   ; 2 signature bytes
        .ascii 'UNA CP/M ROM'           ; 12 signature bytes
        .db 0xDC,0x86                   ; 2 signature bytes
