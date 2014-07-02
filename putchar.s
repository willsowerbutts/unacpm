    .module putchar
    .globl _putchar
    .area _CODE

UNABIOS_CALL                = 0x08      ; entry vector
UNABIOS_OUTPUT_WRITE        = 0x12      ; C register (unit number in B)

; putchar routine for CP/M
_putchar:
    ld hl,#2
    add hl,sp

    ld e, (hl)
    ld bc, #UNABIOS_OUTPUT_WRITE
    rst #UNABIOS_CALL

    ; handle CRLF correctly
    ld a, (hl)
    cp #10
    ret nz
    ld e, #13
    ld bc, #UNABIOS_OUTPUT_WRITE
    rst #UNABIOS_CALL

    ret
