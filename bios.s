    .module bios
    .globl _bios_call
    .globl _boot_cpm
    .area _CODE

_bios_call:
    push ix
    ld ix, #0
    add ix, sp
    push iy
    ld	l,4(ix)
    ld h,5(ix)
    push hl
    ld	l,6(ix)
    ld h,7(ix)
    push hl
    pop iy
    ld c,0(iy)
    ld b,1(iy)
    ld e,2(iy)
    ld d,3(iy)
    ld	l,6(iy)
    ld	h,7(iy)
    push hl
    ld l,4(iy)
    ld h,5(iy)
    pop af
    rst 8
    pop iy
    push af
    ld 5(iy),h
    ld 4(iy),l
    pop hl
    ld 7(iy),h
    ld 6(iy),l
    ld 3(iy),d
    ld 2(iy),e
    ld 1(iy),b
    ld 0(iy),c
    pop iy
    pop ix
    ret

_boot_cpm:
    pop hl      ; return address - we'll never return
    pop hl      ; target address
    jp (hl)     ; jump
