; Z80 CP/M CRT0 for SDCC
; 2013-12-16, 2014-05-26  William R Sowerbutts

        .module runtime0
        .globl init
        .globl _cpminit
        .globl l__INITIALIZER
        .globl s__INITIALIZED
        .globl s__INITIALIZER
        .globl s__GSFINAL

        .area _CODE
        ; this code is loaded at 0x100 by CP/M

init:
        ld  sp, #init_stackptr
    
        ; Initialise global variables
        call    gsinit

        ; Null terminate the command line
        ld hl, #0x0080          ; number of bytes in command line
        ld a, (hl)              ; load byte count
        inc hl                  ; HL points at first byte (0x0081)
        push hl                 ; put on stack (argument to _cpminit)
        add a, l                ; advance to last byte
        or #0x80                ; ensure we do not wrap
        ld l, a                 ; back to L
        xor a                   ; make a zero
        ld (hl), a              ; put terminator in place
    
        ; Call into the C code
        call _cpminit
    
        ; Terminate if main() returns, via BDOS, which is hopefully still present
        ld  c, #0
        call 5
    
; ----------------------------------------
        .area   _STACK
        .ds 256   ; stack memory
init_stackptr:

; ----------------------------------------
        .area   _GSINIT
gsinit::
        ld      bc, #l__INITIALIZER
        ld      a, b
        or      a, c
        jr      z, gsinit_next
        ld      de, #s__INITIALIZED
        ld      hl, #s__INITIALIZER
        ldir
gsinit_next:

; ----------------------------------------
        .area   _GSFINAL
        ret
