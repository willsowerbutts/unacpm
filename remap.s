; UNA CP/M assign program: Find CP/M in ROM, re-run it.
; 2014-07-08 William R Sowerbutts

        .module assign
        .globl l__CODE

        .area _CODE

.include "unabios.inc"

BDOS                        = 0x0005    ; BDOS entry vector

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

        ; check for UNA BIOS presence
        ld hl, (BIOS_IDENTITY_POINTER)
        ld a, (hl)
        cp #BIOS_ID_UNA_BYTE0
        inc hl
        ld a, (hl)
        cp #BIOS_ID_UNA_BYTE1
        jr nz, notuna

        ; smells like UNA.
        ; now examine each page in ROM
        
        ld de, #0
nextrom:
        push de     ; save page number
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        call UNABIOS_STUB_ENTRY ; can't use RST 8 vector
        ; examine ROM 
        ld hl, (0x0004)         ; read pointer at address 4
        ld a, (hl)              ; check signature byte
        cp #0x76
        jr nz, sigfail
        inc hl
        ld a, (hl)              ; check signature byte
        cp #0xB5
        jr nz, sigfail
        ; at this point is is almost certainly a ROM with an identity structure
        inc hl                  ; advance to version number byte
        inc hl                  ; advance to ROM size byte
        inc hl                  ; advance to first byte of version string
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        ; HL now points at the ROM's short description text
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

        ld de, #romfailstr
failexit:
        ld c, #9
        call BDOS

        ; exit via BDOS
        ld  c, #0
        call BDOS

notuna:
        ld de, #unafailstr
        jr failexit

romfailstr:
        .ascii 'Cannot find CP/M ROM page$'

unafailstr:
        .ascii 'This program requires UNA BIOS$'

sigcheck:
        .ascii "UNA CP/M (Will Sowerbutts"   ; remainder of the text varies with version
siglength = . - sigcheck

stack:
        .ds 256
stacktop:

