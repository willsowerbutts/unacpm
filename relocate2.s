    .module relocate2
    .globl _cksum       ; unsigned int
    .globl _dataptr     ; const unsigned char *
    .globl _databit     ; unsigned char
    .globl _relocate_nextbit
    .globl _relocate_nextbyte
    .area _CODE

_relocate_nextbit:
    ld hl, (_dataptr)
    ld a, (_databit)
    ld e, #0
    and (hl)                ; the Z register now reflects if we should return 0 or 1
    jr z, gotbit
    inc e                   ; E now contains our return value
gotbit:
    ld a, (_databit)
    rrca
    ld (_databit), a
    jr nc, done
    ; next byte
    inc hl
    ld (_dataptr), hl
done:
    ld l, e                 ; result goes in L
    ret
    
_relocate_nextbyte:
    ld hl, (_dataptr)
    ld a, (_databit)
    cp #0x80        ; are we byte aligned?
    jr nz, notaligned
    ; we're already aligned, which makes things very simple
    ld a, (hl)
    inc hl
    ld (_dataptr), hl
    ld l, a
    jr updatecksum
notaligned:
    ; now we convert A (with exactly one bit set) into a mask of the bits we need from this byte
    ; eg 0x20 -> 0x3f
    rlca                ; left one bit
    dec a               ; decrement
    ld e, a             ; save mask
    and (hl)            ; mask off desired bits
    ld d, a             ; save result
    ld a, e             ; recover mask
    xor #0xFF           ; invert mask
    inc hl              ; next byte
    ld (_dataptr), hl   ; save new byte ptr
    and (hl)            ; mask off desired bits
    or d                ; merge in bits from first byte
    ld l, a             ; result to L for return
    ld a, (_databit)
    ; now rotate into position
rotateresult:
    rlca                ; rotate bit
    rlc l               ; rotate result byte
    cp #0x80            ; aligned yet?
    jr nz, rotateresult
    ld a, l             ; result back into A
updatecksum:
    ; note result byte is in both L and A at this point
    ld de, (_cksum)     ; load checksum
    add a, e            ; update checksum
    ld e, a             ; low
    jr nc, ckdone
    inc d               ; high
ckdone:
    ld (_cksum), de     ; save checksum
    ret                 ; return with result in L
