; 2014-07-11  Will Sowerbutts <will@sowerbutts.com>

        .module bootdisk

; define the order of our areas
        .area _CODE

buffer    = 0x9000 ; disk buffer (512 bytes)
stacktop  = 0xb000 ; top of stack

.include "unabios.inc"

        .area _CODE
        ; UNA BIOS loads us from disk at 0x8000
        ; supposedly with the boot unit number in register L (2014-07-11 -- it's not there yet)
        ; we must start with a JP or JR instruction.
        jr go
go:     ld sp, #stacktop

        ; write a character
        ld e, #'['
        call printchar

        ; determine the boot unit
        ld bc, #(UNABIOS_BOOT_GET << 8 | UNABIOS_BOOTHISTORY)
        call #UNABIOS_STUB_ENTRY
        ld a, l
        ld (unit), a        ; save boot unit

        ; get the page number for the user memory bank
        ld bc, #(UNABIOS_GET_USER_PAGES << 8 | UNABIOS_GETINFO)
        call #UNABIOS_STUB_ENTRY
        ; returns EXEC_PAGE value in DE

        ; map in user memory bank
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        call #UNABIOS_STUB_ENTRY

        ; write unabios vector in user memory
        ld a, #0xc3         ; jump instruction
        ld (0x0008), a      ; write to memory
        ld hl, #UNABIOS_STUB_ENTRY
        ld (0x0009), hl

nextblock:
        ld e, #'='
        call printchar

        ; set LBA
        xor a
        ld d, a
        ld e, a
        ld h, a
        ld a, (block)
        ld l, a
        inc a               ; setup for next block now
        ld (block), a
        ld c, #UNABIOS_BLOCK_SETLBA
        ld a, (unit)
        ld b, a
        rst #UNABIOS_CALL
        jr nz, error

        ; read block into buffer
        ld c, #UNABIOS_BLOCK_READ
        ld a, (unit)
        ld b, a
        ld l, #1
        ld de, #buffer
        rst #UNABIOS_CALL
        jr nz, error

        ; copy block into low memory
        ld hl, #buffer
        ld e, #0
        ld a, (copyaddr)
        ld d, a
        cp #1               ; the first block?
        jr nz, full
        ld bc, #256         ; do just the top half
        inc h
        jr doldir
full:   ld bc, #512         ; do the full block
doldir: ldir

        ld a, d
        ld (copyaddr), a
        cp #0x80            ; done?
        jr nz, nextblock

        ld e, #']'
        call printchar
        ld e, #0x0d
        call printchar
        ld e, #0x0a
        call printchar

        ; we're loaded. let's go.
        jp 0x100

printchar:
        ld bc, #UNABIOS_OUTPUT_WRITE
        jp UNABIOS_CALL

error:
        ; print the error
        ld a, c
        ld e, a
        call printchar

        ; sad face :(
        ld e, #' '
        call printchar
        ld e, #':'
        call printchar
        ld e, #'('
        call printchar

        ; park the vehicle
        halt

unit:       .db 0
block:      .db 2       ; start loading at sector 2
copyaddr:   .db 1       ; start loading at 0x100, not 0.
