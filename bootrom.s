; 2014-07-02  Will Sowerbutts <will@sowerbutts.com>

        .module bootrom

        .globl init
        .area _CODE

.include "unabios.inc"

; memory values in RAM during bootstrap
; we can use 0x8000 -- 0x803F which is the vector area in ROM, unused in the RAM copy
copyaddr                    = 0x8000    ; 1 byte

; buffer
bouncebuffer                = 0x8100
bouncesize                  = 0x2000    ; must be a factor of 0x8000
; note the 0x100 bytes AFTER bouncebuffer+bouncesize also get overwritten in the first pass of copying

stackbase                   = 0xa100
stacktop                    = 0xa200

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


        .area _CODE
zero:
        ; entry is at 0x0000, executing from ROM
        jp rom_bootstrap                ; jump over vectors -- UNA now provides command line at 0x80--0xFF.
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
        ; boot entry vector in ROM, called by ASSIGN.COM program or by UNA
        ; either way, the command line is loaded into user memory at 0x80 ... 0x100
        ld a, #0x01 ; overwrite RAM from 0x0100 upwards, preserving the CP/M command line
        ld (copyaddr), a
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

        ld bc, #bouncesize
        ld e, #0
        ld a, (copyaddr)                ; to low RAM
        ld d, a
        cp #1                           ; on the first pass we copy to 0x100
        jp nz, gocopy1+0x8000
        dec b                           ; reduce size 0x100 bytes so copyaddr increases just as if we started at zero all along
        ; on the first pass, also install the UNA entry vector
        ld a, #0xc3                     ; jump instruction
        ld (0x0008), a                  ; write to memory
        ld hl, #UNABIOS_STUB_ENTRY
        ld (0x0009), hl
gocopy1:
        ld hl, #bouncebuffer            ; from high memory bounce buffer, above us
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

        ; no longer required as UNA provides command line now
        ; xor a                           ; cold boot -- make an empty command line buffer
        ; ld (0x0080), a                  ; char count
        ; ld (0x0081), a                  ; null terminated string

withcmdline:                            ; can also include first boot
        ld a, #0x76                     ; halt instruction
        ld hl, #0x000B                  ; erase bytes 000B onwards
        ld de, #0x000C
        ld bc, #0x0034                  ; up to the signature location at 0040
        ld (hl), a
        ldir

        ; install a signature (in the same location RomWBW uses)
        ld hl, #0x05B1
        ld (0x0040), hl

        ; we leave user memory mapped in
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
