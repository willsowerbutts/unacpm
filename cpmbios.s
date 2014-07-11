; CP/M 2.2 CBIOS for UNA BIOS for N8VEM
; 2014-06-24  Will Sowerbutts <will@sowerbutts.com>
;
; Based on:
;   CBIOS FOR N8VEM
;   BY ANDREW LYNCH, WITH INPUT FROM MANY SOURCES
;   ROMWBW ADAPTATION BY WAYNE WARTHEN

     .module cpmbios

     ; imported symbols
     .globl FBASE ; BDOS
     .globl CBASE ; CCP
     .globl s__CPMCCP
     .globl s__CPMBIOS
     .globl l__CPMCCP

     ; exported symbols; these are the jump table offsets used by the BDOS
     .globl BOOT
     .globl WBOOT
     .globl CONST
     .globl CONIN
     .globl CONOUT
     .globl LIST
     .globl PUNCH
     .globl READER
     .globl HOME
     .globl SELDSK
     .globl SETTRK
     .globl SETSEC
     .globl SETDMA
     .globl READ
     .globl WRITE
     .globl LISTST
     .globl SECTRN

     .area _CPMBIOS

.include "unabios.inc"

; constant values
TRUE                        = 1
FALSE                       = 0
DOP_READ                    = 0         ; read operation
DOP_WRITE                   = 1         ; write operation
WRT_ALC                     = 0         ; write to allocated
WRT_DIR                     = 1         ; write to directory (priority/forced write)
WRT_UNA                     = 2         ; write to unallocated

; CP/M data addresses
iobyte                      = 3         ; intel "standard" i/o byte
cdisk                       = 4         ; current disk/user number

; Addresses of the fields in the struct persist_t at the top of memory
; remember it's upside-down here.
persist_signature           = 0xFF00 - 2
persist_version             = persist_signature - 1
bufadr                      = persist_version - 2
ccpadr                      = bufadr - 2
config_unit                 = ccpadr - 1
drvcnt                      = config_unit - 1
drvmap                      = drvcnt - 2

; the CP/M BIOS function call dispatch table
;--------------------------------------------------------------------------
BOOT:       jp bios_boot         ; cold start
WBOOT:      jp bios_wboot        ; warm start
CONST:      jp bios_const        ; console status
CONIN:      jp bios_conin        ; console character in
CONOUT:     jp bios_conout       ; console character out
LIST:       jp bios_list         ; list character out
PUNCH:      jp bios_punch        ; punch character out
READER:     jp bios_reader       ; reader character out
HOME:       jp bios_home         ; move disk head to home position
SELDSK:     jp bios_seldsk       ; select disk
SETTRK:     jp bios_settrk       ; set track number
SETSEC:     jp bios_setsec       ; set setor number
SETDMA:     jp bios_setdma       ; set DMA address
READ:       jp bios_read         ; read disk
WRITE:      jp bios_write        ; write disk
LISTST:     jp bios_listst       ; return list status
SECTRN:     jp bios_sectran      ; sector translate
;--------------------------------------------------------------------------

bios_wboot:                 ; warm boot (reload CCP)
            ; put the stack in top 32K
            ld sp, #s__CPMCCP

            ; map in UBIOS memory
            call una_map_ubios

            ; copy CCP back from copy in UNA
            ld de, #s__CPMCCP
            ld hl, (ccpadr)
            ld bc, #l__CPMCCP
            ldir

            ; request UNA map user RAM back into the banked region (0-32K)
            call una_unmap_ubios

            ; fall through
gocpm:      
            ld a, #0xc3     ; 0xc3 is a jmp instruction
            ld (0), a       ; write JMP instruction
            ld hl, #WBOOT   ; warm boot vector
            ld (1), hl      ; write vector for warm boot

            ld (5), a       ; write JMP instruction
            ld hl, #FBASE   ; BDOS entry vector
            ld (6), hl      ; write vector for BDOS entry

            ; reset deblocking algorithm
            call blkres

            ld bc, #0x0080  ; default DMA address
            call setdma     ; configure DMA
            ld a, (cdisk)   ; get current disk
            ld c, a         ; send to ccp
            ; TODO: we assume that current disk is ok (we should probably check!)
            jp CBASE        ; and we're off!

; the LDIR to wipe out the init code in the buffers has to be outside of that region
gocpm_ldir:
            ldir
            jr gocpm

; map UBIOS into low 32K memory (banked region)
; pushes user page number onto caller's stack
; will never destroy HL
una_map_ubios:
            ld de, (ubiospage)
            call una_map
            ; store DE on the caller's stack
            pop bc ; return address
            push de ; save user page number on caller's stack
            push bc ; restore return address
            ; could do pop hl / push de / jp (hl) but that trashes hl
            ret

; map user page back into low 32K memory (banked region)
; pops user page number from caller's stack
una_unmap_ubios:
            pop bc ; return address
            pop de ; user page number from caller's stack
            push bc ; restore return address
            ; fall through

; map page in DE into low 32K memory (banked region)
una_map:
            ld bc, #(UNABIOS_BANK_SET << 8 | UNABIOS_BANKEDMEM)
            rst #UNABIOS_CALL
            ret

bios_const:                 ; console status - return A=0xFF if ready to read, else A=0 if not ready.
            ld bc, #UNABIOS_INPUT_STATUS
            rst #UNABIOS_CALL
            xor a           ; A=0
            cp e            ; E=A?
            ret z           ; not ready
            cpl             ; A=0xFF
            ret             ; ready

bios_conin:                 ; console input, wait if no character queued, return in A
            ld bc, #UNABIOS_INPUT_READ
            rst #UNABIOS_CALL
            ld a, e         ; character read
            and #0x7f       ; clear parity bit
            ret

outchar:    ; wrapper around bios_conout, prints value in A, preserves all registers
            push bc
            push de
            ld c, a
            call bios_conout
            pop de
            pop bc
            ret

bios_conout:                ; console output, character in C
            ld e, c
            ld bc, #UNABIOS_OUTPUT_WRITE
            rst #UNABIOS_CALL
            ret

bios_listst:                ; listing device status
            xor a           ; 0 = not ready
bios_list:                  ; listing device output, character in C
bios_punch:                 ; punch device output, character in C
            ret
bios_reader:                ; reader device input
            ld a, #0x1a     ; end of file
            ret

bios_home:                  ; select track 0 (BC = 0) and fall thru to bios_settrk
            ld a, (hstwrt)  ; check for pending write
            or a            ; set flags
            jr nz, homed    ; buffer is dirty
            ld (hstact), a  ; clear host active flag
homed:
            ld bc, #0
            ; fall through

bios_settrk:                ; set track given by register BC
            ld (sektrk), bc
            ret

bios_setsec:                ; set sector given by register BC
            ld (seksec), bc
            ret

bios_sectran:               ; sector translation for skew, hard coded 1:1, no skew implemented
            ld h, b         ; HL=BC
            ld l, c
            ret

bios_setdma:                ; set DMA address given by register BC
            ld (dmaadr), bc
            ret

;==================================================================================================
;   BLOCKED READ/WRITE (BLOCK AND BUFFER FOR 512 BYTE SECTOR)
;==================================================================================================

blkres:                     ; reset (de)blocking algorithm - just mark buffer invalid
            xor a           ; note: buffer contents invalidated, but retain any pending write
            ld (hstact),a   ; buffer no longer valid
            ld (unacnt),a   ; clear unalloc count
            ret

blkflsh:                    ; flush (de)blocking algorithm - do pending writes
            ; check for buffer written (dirty)
            ld a, (hstwrt)  ; get buffer written flag
            or a
            ret z           ; not dirty, return with a=0 and z set
            ; clear the buffer written flag (even if a write error occurs)
            xor a           ; z = 0
            ld (hstwrt), a  ; save it
            ; do the write and return result
            jp dsk_write

bios_read:                  ; read 128-byte sector
            ld a, #DOP_READ
            jr blkrw

bios_write:                 ; write 128-byte sector
            ld a, c
            ld (wrtype), a  ; save write type
            ld a, #DOP_WRITE
            ; fall through

blkrw:
            ld (dskop), a   ; set the active disk operation
            ; fix!!! we abort on first error, dri seems to pass error status to the end!!!
            ; if write operation, go to special write processing
            cp #DOP_WRITE   ; write?
            jr z, blkrw1    ; go to write processing
            ; otherwise, clear out any sequential, unalloc write processing
            ; and go directly to main i/o
            xor a           ; zero to A
            ld (wrtype), a  ; set write type = 0 (WRT_ALC) to ensure read occurs
            ld (unacnt), a  ; set unacnt to abort seq write processing
            jr blkrw4       ; go to i/o

blkrw1:
            ; write processing
            ; check for first write to unallocated block
            ld a, (wrtype)  ; get write type
            cp #WRT_UNA     ; is it write to unalloc?
            jr nz, blkrw2   ; nope, bypass
            ; initialize start of sequential writing to unallocated block
            ; and then treat subsequent processing as a normal write
            call una_ini    ; initialize sequential write tracking
            xor a           ; A = 0 = WRT_ALC
            ld (wrtype), a  ; now treat like write to allocated

blkrw2:
            ; if wrtype = WRT_ALC and seq write, goto blkrw7 (skip read)
            or a            ; note: A will already have the write type here
            jr nz, blkrw3   ; not type = 0 = WRT_ALC, so move on
            call una_chk    ; check for continuation of seq writes to unallocated block
            jr nz, blkrw3   ; nope, abort
            ; we matched everything, treat as write to unallocated block
            ld a, #WRT_UNA  ; write to unallocated
            ld (wrtype), a  ; save write type
            call una_inc    ; increment sequential write tracking
            jr blkrw4       ; proceed to i/o processing

blkrw3:
            ; non-sequential write detected, stop any further checking
            xor a           ; zero
            ld (unacnt), a  ; clear unallocated write count
            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
            ; is a flush needed here???
            ; flush current buffer contents if needed
            ;call   blkflsh     ; flush pending writes
            ;ret    nz      ; abort on error
            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

blkrw4:
            ; start of actual i/o processing
            call blk_xlt    ; do the logical to physical mapping: sek... -> xlt...
            call blk_cmp    ; is the desired physical block in buffer?
            jr z, blkrw6    ; block already in active buffer, no read required
            ; at this point, we know we need to read the target physical sector
            ; it may actually be a preread for a subsequent write, but that is ok
            ; first, flush current buffer contents
            call blkflsh    ; flush pending writes
            ret nz          ; abort on error
            ; implement the translated values
            call blk_sav    ; save xlat values: xlt... -> hst...
            ; if write to unalloc block, bypass read, leaves buffer undefined
            ld a, (wrtype)
            cp #WRT_UNA
            jr z, blkrw6
            ; do the actual read
            call dsk_read   ; read physical sector into buffer
            jr z, blkrw6    ; good read, continue
            ; if read failed, reset (de)blocking algorithm and return error
            push af         ; save error status
            call blkres     ; invalidate (de)blocking buffer
            pop af          ; recover error status
            ret             ; error return

blkrw6:
            ; check type of operations, if write, then go to write processing
            ld a, (dskop)   ; get pending operation
            cp #DOP_WRITE   ; is it a write?
            jr z, blkrw7    ; yes, go to write processing
            ; this is a read operation, we already did the i/o, now just deblock and return
            call blk_deblock ; extract data from block
            xor a           ; no error
            ret             ; all done
    
blkrw7:
            ; this is a write operation, insert data into block
            call blk_block  ; insert data into block
            ; mark the buffer as written
            ld a, #TRUE     ; buffer dirty = true
            ld (hstwrt), a  ; save it
            ; check write type, if wrt_dir, force the physical write
            ld a, (wrtype)  ; get write type
            cp #WRT_DIR     ; 1 = directory write
            jp z, blkflsh   ; flush pending writes and return status
            xor a       ; all is well, set return code 0
            ret         ; return

; setup una... variables
una_ini:                    ; initialize tracking of sequential writes into unallocated block
            ; copy sekdsk/trk/sec to una...
            ld hl, #sek
            ld de, #una
            ld bc, #UNASIZ
            ldir

            ; setup unacnt and unaspt
            ld hl, (sekdph) ; hl points to dph
            ld de, #10      ; offset of dpb address in dph
            add hl, de      ; dph points to dpb address
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a         ; hl points to dpb
            ld c, (hl)
            inc hl
            ld b, (hl)      ; bc has spt
            ld (unaspt), bc ; save sectors per track
            dec hl
            dec hl          ; hl points to records per block (byte in front of dpb)
            ld a, (hl)      ; get it
            ld (unacnt), a  ; save it
            ret

; check for continuation of sequential writes to unallocated block
; see if unacnt > 0 and una... variables match sek... variables
una_chk:
            ld a, (unacnt)  ; get the counter
            or a
            jr nz, una_chk1 ; if not done with block, keep checking
            ; cnt is now zero, exhausted records in one block!
            dec a           ; hack to set nz
            ret             ; return with nz

una_chk1:
            ; compare una... variables with sek... variables
            ld hl, #sek
            ld de, #una
            ld b, #unasiz
            jr blk_cmploop

; increment the sequential write tracking variables
; to reflect the next record (trk/sec) we expect
una_inc:
            ; decrement the block record count
            ld hl, #UNACNT
            dec (hl)
            ; increment the sector
            ld de, (unasec)
            inc de
            ld (unasec), de
            ; check for end of track
            ld hl, (unaspt)
            xor a
            sbc hl, de
            ret nz
            ; handle end of track
            ld (unasec), hl ; sector back to 0 (note: hl=0 at this point)
            ld hl, (unatrk) ; get current track
            inc hl          ; bump it
            ld (unatrk), hl ; save it
            ret

; translate from cp/m dsk/trk/sec to physical
; sek... -> xlt...
blk_xlt:
            ; first, do a byte copy of sek... to xlt...
            ld hl, #sek
            ld de, #xlt
            ld bc, #xltsiz
            ldir

            ; now update xltsec based on (de)blocking factor (always 4:1)
            ld bc, (seksec) ; sector is factored down (4:1) due to blocking
            srl b           ; 16 bit right shift twice to divide by 4
            rr c
            srl b
            rr c
            ld (xltsec), bc

            ret
; save results of translation: xlt... -> hst...
; implicitly sets hstact to true!
blk_sav:
            ld hl, #xlt
            ld de, #hst
            ld bc, #xltsiz
            ldir
            ret

; compare results of translation to current buf (xlt... to hst...)
; note that hstact is compared to xltact implicitly!  xltact is always true, so
; hstact must be true for compare to succeed.
blk_cmp:
            ld hl, #xlt
            ld de, #hst
            ld b,  #xltsiz
blk_cmploop:
            ld a, (de)
            cp (hl)
            ret nz          ; bad compare, return with nz
            inc hl
            inc de
            djnz blk_cmploop
            ret             ; return with z

; block data - insert cpm dma buf into proper part of physical sector buffer
blk_block:
            ld hl, (dmaadr)
            bit 7, h            ; test top bit of H
            jr nz, blk_block_go
            ; copy data to our bounce buffer first
            ld de, #bouncebuf
            ld bc, #128
            ldir
blk_block_go:
            call una_map_ubios
            call blk_setup      ; BC=128, HL=buffer address, DE=DMA address
            ex de, hl           ; put buffer address in DE
            bit 7, h            ; test top bit of H again
            jr nz, blk_block_go2
            ld hl, #bouncebuf
blk_block_go2:
            ldir
            call una_unmap_ubios
            ret

; deblock data - extract desired cpm dma buf from physical sector buffer
blk_deblock:
            call una_map_ubios
            call blk_setup      ; BC=128, HL=buffer address, DE=DMA address
            bit 7, d            ; test top bit of D
            jr nz, blk_deblock_go
            ; low memory DMA; need to use our bounce buffer in high memory
            ld de, #bouncebuf
blk_deblock_go:
            ldir                ; copy data
            call una_unmap_ubios
            ld de, (dmaadr)     ; test DMA address again
            bit 7, d
            ret nz              ; high memory - complete.
            ; low memory DMA; bounce the data from high to low memory
            ld hl, #bouncebuf
            ld bc, #128
            ldir
            ret

; setup source and destination pointers for block copy operation
; at exit, hl = address of desired block in sector buffer, de = dma buffer address
blk_setup:
            ld bc, (seksec)
            ld a, c
            and #3          ; a = index of cpm buf in sec buf
            rrca            ; multiply by 64
            rrca
            ld e, a         ; into low order byte of destination
            ld d, #0        ; high order byte is zero
            ld hl, (bufadr) ; hl = start of sector buffer (in UNA bank)
            add hl, de      ; add in computed offset
            add hl, de      ; hl now = index * 128 (source)
            ld de, (dmaadr) ; de = destination = dma buf
            ld bc, #128     ; bc = sector length
            ret

; lookup disk information based on cpm drive in C
; on return, C=requested drive, B=device/unit, HL=DPH address, DE=ptr to first LBA
dsk_getinf:
            ld a, (drvcnt)  ; A = defined drive count
            dec a           ; now A = highest valid drive number
            cp c            ; compare with requested drive
            jr c, dsk_getinf1 ; if out of range,  go to error return
            ld hl, (drvmap) ; HL := start of drive map
            ld a, c         ; A = drive #
            ; compute HL = HL + 8 * A
            rlca
            rlca
            rlca
            call addhla     ; HL = HL + A
            ld b, (hl)      ; B := device/unit
            inc hl          ; advance to DPH
            ld e, (hl)      ; load DPH
            inc hl          ; ... into
            ld d, (hl)      ; ... DE
            inc hl          ; advance to point at LBA
            ex de, hl       ; put DPH in HL, LBA ptr in DE
            xor a           ; set success
            ret
dsk_getinf1:                ; error return
            xor a
            ld h, a
            ld l, a
            ld d, a
            ld e, a
            ld b, a
            inc a
            ret

; compute HL = HL + A
addhla:     add a, l
            ld l, a
            ret nc
            inc h
            ret

bios_seldsk:                ; select disk number (in C) for subsequent disk ops
dsk_select:
            call dsk_getinf ; C unmodified, B=unit, DE=LBA ptr, HL=DPH ptr
            jr nz, dsk_select_error
            ld a, c         ; A := cpm drive no
            ld (sekdsk), a  ; save it
            ld a, b         ; A := device/unit
            ld (sekdu), a   ; save device/unit
            ld (sekdph), hl ; save DPH pointer
            ld (sekoff), de ; save LBA pointer
            xor a           ; flag success
            ret             ; normal return, with DPH in HL
dsk_select_error:           ; user tried to select an invalid disk
            xor a
            ld (cdisk), a   ; switch them back to A: to avoid the need to reboot
            ret             ; return with HL=0 to indicate error

dsk_read:
            ld c, #UNABIOS_BLOCK_READ
            jr dsk_io

dsk_write:
            ld c, #UNABIOS_BLOCK_WRITE
            ; fall through to dsk_io

dsk_io:
            ; assumes all device use LBA
            push bc             ; save function number for later

            ; coerce track/sector into DE:HL as 0000:ttts
            ld hl, (hsttrk)
            ld b, #4            ; prepare to left shift by 4 bits
dsk_io3:
            sla l               ; shift de left by 4 bits
            rl h
            djnz dsk_io3        ; loop till all 4 bits done
            ld a, (hstsec)      ; get the sector into a
            and #0x0f           ; get rid of top nibble
            or l                ; combine with e
            ld l, a             ; back in e
            ld de, #0           ; DE:HL now has slice relative LBA

            ; LBA is in DE:HL is relative to start of slice; now add in the unit partition/slice offset
            push ix             ; save IX register
            ld ix, (hstoff)     ; pointer to LBA of first block

            ; 32-bit addition  DE:HL = DE:HL + (IX)
            ld a, l
            add a, 0(ix)
            ld l, a

            ld a, h
            adc a, 1(ix)
            ld h, a

            ld a, e
            adc a, 2(ix)
            ld e, a

            ld a, d
            adc a, 3(ix)
            ld d, a
            pop ix              ; restore IX register

            ld c, #UNABIOS_BLOCK_SETLBA ; function
            ld a, (hstdu)       ; unit number
            ld b, a
            rst #UNABIOS_CALL   ; UNA BIOS call: set LBA for next transfer
            pop hl              ; recover function number, una_map_ubios does not destroy HL
            jr nz, ioerror_c    ; handle any error condition arising from set LBA BIOS call

            call una_map_ubios  ; pushes page number onto stack
            ld c, l             ; move function number (read/write) into C

            ld a, (hstdu)       ; unit number ...
            ld b, a             ; ... in B
            ld de, (bufadr)     ; buffer address (in UNA memory bank)
            ld l, #1            ; single sector transfer
            rst #UNABIOS_CALL   ; UNA BIOS call: read/write storage device
            ld h, c             ; save result (C) in H

            call una_unmap_ubios; pops from our stack

            xor a               ; A=0
            cp h                ; io result was 0?
            ret z               ; yes - return A=0 on success
ioerror:    ld de, #ioerrmsg    ; no - report error
            call printstring
            ld a, h
            call printahex
            xor a
            inc a               ; clears Z flag
            ret                 ; return A=1, flags NZ on error
ioerror_c:  ld h, c             ; move error code from C into H
            jr ioerror          ; jump into main ioerror routine

printstring:    ; print string in DE
            push bc
            push hl
            ld c, #UNABIOS_OUTPUT_WRITE_STRING
            ld b, #0
            ld l, #0
            rst #UNABIOS_CALL
            pop hl
            pop bc
            ret

printahex:
            push bc
            ld c, a  ; copy value
            ; print the top nibble
            rra
            rra
            rra
            rra
            call printnibble
            ; print the bottom nibble
            ld a, c
            call printnibble
            pop bc
            ret

printnibble:
            and #0x0f ; mask off low four bits
            cp #10
            jr c, pnumeral ; less than 10?
            add #0x07 ; start at 'A' (10+7+0x30=0x41='A')
pnumeral:   add #0x30 ; start at '0' (0x30='0')
            call outchar
            ret

; -------------------------------------------------------------------------
; Messages available at all times

crlf:       .ascii "\r\n"
            .db 0
ioerrmsg:   .ascii "\r\nIO error 0x"
            .db 0
; -------------------------------------------------------------------------
; Data structures

dskop:      .db     0           ; current disk operation (DOP_* constants)
wrtype:     .db     0           ; write type (WRT_* constants)
dmaadr:     .dw     0           ; disk I/O buffer address
hstwrt:     .db     0           ; buffer dirty?
ubiospage:  .dw     0           ; UBIOS page number

; -------------------------------------------------------------------------

; DISK I/O REQUEST PENDING
sek:
sekdsk:     .db     0       ; disk number 0-15
sektrk:     .dw     0       ; two bytes for track # (logical)
seksec:     .dw     0       ; two bytes for sector # (logical)
sekdu:      .db     0       ; device/unit
sekdph:     .dw     0       ; address of active (selected) dph
sekoff:     .dw     0       ; track offset in effect for lu
sekact:     .db     TRUE    ; always true!

; RESULT OF CPM TO PHYSICAL TRANSLATION
xlt:
xltdsk:     .db     0
xlttrk:     .dw     0
xltsec:     .dw     0
xltdu:      .db     0
xltdph:     .dw     0
xltoff:     .dw     0
xltact:     .db     TRUE    ; always true!
XLTSIZ      =       ( . - XLT)

; DSK/TRK/SEC IN BUFFER (VALID WHEN HSTACT=TRUE)
hst:
hstdsk:     .db     0       ; disk in buffer
hsttrk:     .dw     0       ; track in buffer
hstsec:     .dw     0       ; sector in buffer
hstdu:      .db     0       ; device/unit in buffer
hstdph:     .dw     0       ; current dph address
hstoff:     .dw     0       ; track offset in effect for lu
hstact:     .db     0       ; true = buffer has valid data

; SEQUENTIAL WRITE TRACKING FOR UNALLOCATED BLOCK
una:
unadsk:     .db     0       ; disk number 0-15
unatrk:     .dw     0       ; two bytes for track # (logical)
unasec:     .dw     0       ; two bytes for sector # (logical)
;
UNASIZ      =       (. - una)

unacnt:     .db     0       ; count down unallocated records in block
unaspt:     .dw     0       ; sectors per track

; -------------------------------------------------------------------------
; POST-BOOT BUFFERS (SHARED WITH INITIALISATION CODE)
; -------------------------------------------------------------------------
; We need a number of large data structures for the BDOS. Most of these are not
; used until after the BOOT BIOS call has completed, and BOOT is not required
; again. Therefore we store the code and data required only at cold start here.
;
; Declare the shared data structures as empty space.
; These cannot be used before "boot" completes!
; These must be not require initialised values (.ds only)!
postboot_data_start:            ; -- START POST-BOOT BUFFERS --
bouncebuf:  .ds 128             ; low memory DMA bounce buffer
postboot_data_end:              ; -- END POST-BOOT BUFFERS --
postboot_data_len = postboot_data_end - postboot_data_start

; -------------------------------------------------------------------------
; START OF MEMORY SHARED WITH POST-BOOT BUFFERS
; -------------------------------------------------------------------------
; rewind the output pointer, overwrite the buffer space with our init code.
. = . - postboot_data_len
init_code_start:

bios_boot:
            ; put the stack in top 32K
            ld sp, #s__CPMCCP

            ; say hello
            ld de, #bootmsg
            call printstring

            ; locate UNA's page in memory
            ld bc, #(UNABIOS_GET_PAGE_NUMBERS << 8 | UNABIOS_GETINFO)
            rst #UNABIOS_CALL
            ld (ubiospage), hl

            ; perform standard CP/M initialisation
            xor a
            ld (iobyte), a
            ld (cdisk), a

            ; map in UNA memory page
            call una_map_ubios

            ; copy CCP to buffer in UNA memory
            ld hl, #s__CPMCCP
            ld de, (ccpadr)
            ld bc, #l__CPMCCP
            ldir

            ; map in user memory page
            call una_unmap_ubios

            ; patch BOOT system call to point at WBOOT instead.
            ld hl, #bios_wboot
            ld (BOOT+1), hl

            ; finally, set up for ldir to wipe out the buffers region -- not strictly required but useful for debugging blunders
            ld hl, #postboot_data_start
            ld de, #postboot_data_start+1
            ld bc, #postboot_data_len-1 ; we'll write the first byte
            ld a, #0x00
            ld (hl), a ; write first byte

            ; continue boot
            jp gocpm_ldir

bootmsg:    .ascii "CP/M 2.2 Copyright 1979 (c) by Digital Research"
            .ascii "\r\n"
            .db 0

; safety check to ensure we do not overflow the available space
; ** we could allow more space if we could guarantee we were followed by some uninitialised buffer, eg dirbuf?
; ** how to communicate the required runtime versus load time size to the initialisation code?
init_code_len = (. - init_code_start)
.ifgt (init_code_len - postboot_data_len) ; > 0 ?
; cause an error (.msg, .error not yet supported by sdas which itself is an error)
.msg "Init code/data is too large"
.error 1
.endif
; end of init code and data
; pad buffers to length ---------------------------------------------------
             .ds postboot_data_len - (. - init_code_start) - 1 ; must be last
             .db 0x00 ; write a value into the final byte so srec_cat outputs a file of the required size
; -------------------------------------------------------------------------
; END OF MEMORY SHARED WITH POST-BOOT BUFFERS
; -------------------------------------------------------------------------

;; ; safety check to ensure we do not overflow into the UBIOS stub at 0xFF00
;; cbios_length = . - BOOT
;; .ifgt cbios_length - (UNABIOS_STUB_START - CBIOS_START) ; > 0 ?
;; ; cause an error (.msg, .error not yet supported by sdas which itself is an error)
;; .msg "CBIOS is too large"
;; .error 1
;; .endif
