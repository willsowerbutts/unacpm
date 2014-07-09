; UNA CP/M assign program: Find CP/M in ROM, re-run it.
; 2014-07-08 William R Sowerbutts

        .module assign
        .globl l__CODE

        .area _CODE

BDOS                        = 0x0005    ; BDOS entry vector
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

        ; this code is loaded at 0x100 by CP/M
        ; we want it to run at 0x8000
        ; copy it there
        ld hl, #0x100           ; source address
        ld bc, #l__CODE         ; length
        ld de, #0x8000          ; destination
        ldir                    ; copy
        jp continue
continue:
        ; now we're in high memory

        ; hoist the stack up here too
        ld sp, #stacktop

        ; examine each page in ROM
        
        ; we know it won't be in page 0, so start with page 1.
        ld de, #1
nextrom:
        push de     ; save page number
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        call UNABIOS_STUB_ENTRY ; can't use RST 8 vector
        ; examine ROM 
        ld hl, #(0x100 - siglength)
        ld de, #sigcheck
        ld b, #siglength
checkbyte:
        ld a, (de)
        cp (hl)
        jr nz, sigfail
        inc hl
        inc de
        djnz checkbyte
sigpass:
        ; found the ROM!
        jp 0x0040 ; jump right on in to the bootstrap.
sigfail:
        ; next page in ROM
        pop de
        inc de
        ld a, e
        cp #16            ; check first 512K of ROM
        jr nz, nextrom

        ; ok, we can't find the ROM. Abort.

        ; get the page number for the user memory bank
        ld bc, #(UNABIOS_GET_USER_PAGES << 8 | UNABIOS_GETINFO)
        call UNABIOS_STUB_ENTRY
        ; returns EXEC_PAGE value in DE
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        call UNABIOS_STUB_ENTRY

        ld de, #failstr
        ld c, #UNABIOS_OUTPUT_WRITE_STRING
        ld b, #0
        ld l, #0
        call UNABIOS_STUB_ENTRY

        ; exit via BDOS
        ld  c, #0
        call BDOS

failstr:
        .ascii 'Cannot find CP/M ROM page'
        .db 13, 10, 0
sigcheck:
        .db 0x05,0xCA                   ; 2 signature bytes
        .ascii 'UNA CP/M ROM'           ; 12 signature bytes
        .db 0xDC,0x86                   ; 2 signature bytes
siglength = . - sigcheck
stack:
        .ds 256
stacktop:

