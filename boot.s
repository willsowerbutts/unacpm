; CBIOS for UNA BIOS for N8VEM
; 2014-06-18  Will Sowerbutts <will@sowerbutts.com>

        .module cpmboot

        ; imported symbols
        .globl s__CPMCCP
        .globl l__CPMBIOS
        .globl l__BOOTSTRAP
        .globl BOOT

; define the order of our areas
        .area _BOOTSTRAP
        .area _CPMCCP
        .area _CPMBDOS
        .area _CPMBIOS

EXEC_PAGE               .equ 0x8000     ; RAM_0
UNABIOS_CALL            .equ 0x08       ; entry vector
UNABIOS_BANKEDMEM       .equ 0xFB       ; C register (subfunction in B)
UNABIOS_BANK_GET        .equ 0x00       ;   B register (subfunction)
UNABIOS_BANK_SET        .equ 0x01       ;   B register (subfunction)
UNABIOS_STUB_ENTRY      .equ 0xFF80     ; main UNA entry vector
CPM_LOAD_ADDRESS        .equ 0x0200     ; offset of CP/M image in ROM page

        .area _BOOTSTRAP
zero:
        ; entry is at 0x0000, executing from ROM
        jp bootstrap                    ; jump over vectors
        
        .ds 8 - (. - zero)              ; space until the RST 8 vector
        jp UNABIOS_STUB_ENTRY           ; UNA RST 8 entry vector

        .ds 0x100 - (. - zero)          ; to make a .COM file, just strip off the first 0x100 bytes of the ROM image
bootstrap:
        di                              ; disable interrupts, just in case.
        ld sp, #s__CPMCCP               ; put stack at top of TPA

        ; CP/M is linked to run at the top of memory, but is
        ; loaded from 0x400 upwards. Copy it to the correct
        ; location.
        ld de, #s__CPMCCP
        ld hl, #CPM_LOAD_ADDRESS
        ld bc, #(l__CPMBIOS + 0x1600)   ; CCP+BDOS is 5.5KB (0x1600 bytes)
        ldir                            ; copy code into final position

        ; Copy this bootstrap code up into the upper 32K
        ld de, #0x8000                  ; to 32K
        ld hl, #0x0000                  ; from entry vector
        ld bc, #l__BOOTSTRAP            ; copy entire bootstrap
        ldir
        jp continue+0x8000 ; jump to copy of next instruction, above 32K

        ; -- careful with labels after here -- they will be offset 32K --

continue:
        ; Request UNA map user RAM back into the 0--32KB banked region.
        ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
        ld de, #EXEC_PAGE
        rst #UNABIOS_CALL               ; can use this; we place the vector in ROM

        ; wipe out any existing vectors with HALT instructions
        ld de, #1
        ld hl, #0
        ld bc, #63
        ld (hl), #0x76                  ; 0x76 is a HALT instruction
        ldir

        ; install UNA entry vector in RAM
        ld a, #0xc3                     ; 0xc3 is a JP instruction
        ld (8), a                       ; write JP instruction at 0x0008
        ld hl, #UNABIOS_STUB_ENTRY
        ld (9), hl                      ; write entry vector at 0x0009

        ; install a signature (in the same location RomWBW uses)
        ld hl, #0x05B1
        ld (0x0040), hl

        ; showtime
        jp BOOT                         ; Boot!
