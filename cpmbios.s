; CP/M 2.2 CBIOS for UNA BIOS for N8VEM
; 2014-06-24  Will Sowerbutts <will@sowerbutts.com>
;
; Based (almost entirely!) on:
;   CBIOS FOR N8VEM
;   BY ANDREW LYNCH, WITH INPUT FROM MANY SOURCES
;   ROMWBW ADAPTATION BY WAYNE WARTHEN

; TODO:
; - check UNA BIOS version number on startup
; - check status byte in each partition entry is not in range 0x01--0x7F,
;   reject entire device if so(?)
; - check device size is >= 2MB before examining partition table (or check type?)
; - where MBR present but no 0x32 partition, use the lowest LBA of
;   any foreign partition as the extent to compute # slices
;   - EXCEPT for some as yet to be agreed "protective" partition type

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

; load address (used to check we don't overflow into CBIOS)
CBIOS_START                 = 0xF600    ; update this when changing cpm.lnk

; during boot we need a temporary buffer of 512 bytes in the top 32K
SECTOR_BUFFER               = 0x8000    ; cpmboot.s already overwrites this address

; UNA BIOS interface details
UNABIOS_STUB_START          = 0xFF00    ; UNA BIOS stub start
UNABIOS_STUB_ENTRY          = 0xFF80    ; main UNA entry vector
UNABIOS_CALL                = 0x08      ; entry vector
UNABIOS_GETINFO             = 0xFA      ; C regsister (subfunction in B)
UNABIOS_GET_SIGNATURE       = 0x00      ;   B register (GETINFO subfunction)
UNABIOS_GET_STRING_SHORT    = 0x01      ;   B register (GETINFO subfunction)
UNABIOS_GET_STRING_LONG     = 0x02      ;   B register (GETINFO subfunction)
UNABIOS_GET_PAGE_NUMBERS    = 0x03      ;   B register (GETINFO subfunction)
UNABIOS_GET_VERSION         = 0x04      ;   B register (GETINFO subfunction)
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
; on return, D=device/unit, E=slice, HL=DPH address
dsk_getinf:
            ld a, c         ; A := cpm drive
            cp #DRVCNT      ; compare to number of drives configured
            jr nc, dsk_getinf1 ; if out of range,  go to error return
            ld hl, #drvmap  ; HL := start of drive map
            rlca            ; multiply a by 4...
            rlca            ; to use as offset into drvmap
            call addhla     ; add offset
            ld d, (hl)      ; D := device/unit
            inc hl          ; bump to slice
            ld e, (hl)      ; E := slice
            inc hl          ; point to dph lsb
            ld a, (hl)      ; A := dph lsb
            inc hl          ; point to dph msb
            ld h, (hl)      ; H := dph msb
            ld l, a         ; L := dph lsb
            xor a           ; set success
            ret
dsk_getinf1:                ; error return
            xor a
            ld h, a
            ld l, a
            ld d, a
            ld e, a
            inc a
            ret

; compute HL = HL + A
addhla:     add a, l
            ld l, a
            ret nc
            inc h
            ret

; multiply 8-bit values
; in:  multiply h by e
; out: hl = result, e = 0, b = 0
mult8:      ld d, #0
            ld l, d
            ld b, #8
mult8_loop: add hl, hl
            jr nc, mult8_noadd
            add hl, de
mult8_noadd: djnz mult8_loop
            ret

bios_seldsk:                ; select disk number for subsequent disk ops
dsk_select:
            ld b, e         ; save e in b for now
            call dsk_getinf ; get D=device/unit, E=slice, HL=dph address
            ret nz          ; return if invalid drive (A=1, NZ set, HL=0)
            push bc         ; we need B later, save on stack

            ; save all the new stuff
            ld a, c         ; A := cpm drive no
            ld (sekdsk), a  ; save it
            ld a, d         ; A := device/unit
            ld (sekdu), a   ; save device/unit
            ld (sekdph), hl ; save DPH pointer

            ; update offset for active slice
            ; a track is assumed to be 16 sectors
            ; the offset represents the number of blocks * 256
            ; to use as the offset
            ld h, #65       ; h = tracks per slice,  e = slice no
            call mult8      ; hl := h * e (total track offset)
            ld (sekoff), hl ; save new track offset

            pop bc          ; get original e into b
            ; WRS: we just use static DPBs for the time being (keeping it simple)
            ;; ; check if this is login,  if not,  bypass media detection
            ;; ; fix: what if previous media detection failed???
            ;; bit 0, b        ; test drive login bit
            ;; jr nz, dsk_select2 ; bypass media detection

            ;; ; determine media in drive
            ;; ld a, (sekdu)   ; get device/unit
            ;; ld c, a         ; store in c
            ;; ld b, bf_diomed ; driver function = disk media
            ;; rst 08
            ;; or a            ; set flags
            ;; ld hl, 0        ; assume failure
            ;; ret z           ; bail out if no media

            ;; ; a has media id,  set hl to corresponding dpbmap entry
            ;; ld hl, dpbmap   ; hl = dpbmap
            ;; rlca            ; dpbmap entries are 2 bytes each
            ;; call addhla     ; add offset to hl

            ;; ; lookup the actual dpb address now
            ;; ld e, (hl)      ; dereference hl...
            ;; inc hl          ; into de...
            ;; ld d, (hl)      ; bc = address of desired dpb

            ;; ; plug dpb into the active dph
            ;; ld hl, (sekdph)
            ;; ld bc, 10       ; offset of dpb in dph
            ;; add hl, bc      ; hl := dph.dpb
            ;; ld (hl), e      ; set lsb of dpb in dph
            ;; inc hl          ; bump to msb
            ;; ld (hl), d      ; set msb of dpb in dph
dsk_select2:
            ld hl, (sekdph) ; hl = dph address for cp/m 
            xor a           ; flag success
            ret             ; normal return

dsk_read:
            ld c, #UNABIOS_BLOCK_READ
            jr dsk_io

dsk_write:
            ld c, #UNABIOS_BLOCK_WRITE
            ; fall through to dsk_io

dsk_io:
            ; assumes all device use LBA
            push ix         ; save IX register
            push bc         ; save function number for later

            ; load partition offset
            ld hl, #unit_slice_info
            ld a, (hstdu)
            add a, a        ; *2
            ld c, a         ; save *2
            add a, a        ; *4
            add a, c        ; *6
            add l
            ; HL += A
            ld l, a
            jr nc, dsk_io2
            inc h
dsk_io2:    push hl         ; store offset to LBA
            
            ; coerce track/sector into HL:DE as 0000:ttts
            ld de, (hsttrk)
            ld b, #4            ; prepare to left shift by 4 bits
dsk_io3:
            sla e               ; shift de left by 4 bits
            rl d
            djnz dsk_io3        ; loop till all 4 bits done
            ld a, (hstsec)      ; get the sector into a
            and #0x0f           ; get rid of top nibble
            or e                ; combine with e
            ld e, a             ; back in e
            ld hl, #0           ; hl:de now has slice relative lba
            ; apply slice offset now
            ; slice offset is expressed as number of blocks * 256 to offset!
            ld a, (hstoff)      ; lsb of slice offset to a
            add a, d            ; add with d
            ld d, a             ; put it back in d
            ld a, (hstoff+1)    ; msb of slice offset to a
            call addhla         ; add offset
            ex de, hl           ; LBA is in HL:DE but we want it in DE:HL for UNA
            ; LBA is in DE:HL is relative to start of partition; add in unit partition offset

            ; apply partition offset now
            pop ix              ; recover partition LBA pointer

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

            ld c, #UNABIOS_BLOCK_SETLBA ; function
            ld a, (hstdu)       ; unit number
            ld b, a
            rst #UNABIOS_CALL   ; UNA BIOS call: set LBA for next transfer

            pop hl              ; una_map_ubios does not destroy HL
            call una_map_ubios  ; pushes page number onto stack
            ld c, l             ; recover function number (read/write) into C

            ld a, (hstdu)       ; unit number ...
            ld b, a             ; ... in B
            ld de, (bufadr)     ; buffer address (in UNA memory bank)
            ld l, #1            ; single sector transfer
            rst #UNABIOS_CALL   ; UNA BIOS call: read/write storage device
            ld h, c             ; save result (C) in H

            call una_unmap_ubios; pops from our stack

            pop ix              ; restore IX register
            xor a               ; A=0
            cp h                ; io result was 0?
            ret z               ; yes - return A=0 on success
ioerror:    ; this section is used by initialisation for I/O errors also
            ld de, #ioerrmsg    ; no - report error
            call printstring
            ld a, h
            call printahex
            xor a
            inc a               ; clears Z flag
            ret                 ; return A=1, flags NZ on error

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
bufadr:     .dw     0           ; address of disk sector buffer (in UNA bank!)
ccpadr:     .dw     0           ; address of CCP copy (in UNA bank!)
ubiospage:  .dw     0           ; UBIOS page number

; Drive map: table with 4 bytes per drive
; Statically configured for now (trying to keep things simple!)
drvmap:
            ; drive A:
            .db     0           ; unit number
            .db     0           ; slice number
            .dw     dph_drv_a   ; DPH address
            ; drive B:
            .db     1           ; unit number
            .db     0           ; slice number
            .dw     dph_drv_b   ; DPH address
            ; drive C:
            .db     2           ; unit number
            .db     0           ; slice number
            .dw     dph_drv_c   ; DPH address
            ; drive D:
            .db     3           ; unit number
            .db     0           ; slice number
            .dw     dph_drv_d   ; DPH address

DRVCNT      =       (( . - drvmap ) / 4)    ; number of defined drives

; Number of units we will support (ie physical devices, before slicing)
UNITCNT     =       4

; LBA of sliced CP/M storage area on each unit (physical device)
unit_slice_info:
            .rept   UNITCNT
            .db     0,0,0,0     ; start LBA on unit
            .db     0,0         ; number of slices on unit
            .endm

; -------------------------------------------------------------------------

; Disk Parameter Header (16 bytes per drive)
dph_drv_a:
            .dw     0           ; XLT = 0: no translation
            .dw     0, 0, 0     ; BDOS scratchpad
            .dw     dirbf       ; shared directory buffer
            .dw     dpb_hdd     ; pointer to disk parameter block (can be shared)
            .dw     0           ; checksum vector (unused for non-removable storage)
            .dw     alv_drv_a   ; allocation vector
dph_drv_b:
            .dw     0           ; XLT = 0: no translation
            .dw     0, 0, 0     ; BDOS scratchpad
            .dw     dirbf       ; shared directory buffer
            .dw     dpb_hdd     ; pointer to disk parameter block (can be shared)
            .dw     0           ; checksum vector (unused for non-removable storage)
            .dw     alv_drv_b   ; allocation vector
dph_drv_c:
            .dw     0           ; XLT = 0: no translation
            .dw     0, 0, 0     ; BDOS scratchpad
            .dw     dirbf       ; shared directory buffer
            .dw     dpb_hdd     ; pointer to disk parameter block (can be shared)
            .dw     0           ; checksum vector (unused for non-removable storage)
            .dw     alv_drv_c   ; allocation vector
dph_drv_d:
            .dw     0           ; XLT = 0: no translation
            .dw     0, 0, 0     ; BDOS scratchpad
            .dw     dirbf       ; shared directory buffer
            .dw     dpb_hdd     ; pointer to disk parameter block (can be shared)
            .dw     0           ; checksum vector (unused for non-removable storage)
            .dw     alv_drv_d   ; allocation vector

; -------------------------------------------------------------------------

; Disk Parameter Block for 8MB HDD (15 bytes per DPB, can be shared between drives)
dpb_hdd:
            .dw     64          ; SPT: sectors per track
            .db     5           ; BSH: block shift factor
            .db     31          ; BLM: block mask
            .db     1           ; EXM: extent mask
            .dw     2047        ; DSM: total blocks of storage - 1 (2048 * 128 * 32 = 8MB)
            .dw     511         ; DRM: total directory entries - 1
            .db     0xf0        ; AL0: allocation vector for directory, first byte
            .db     0x00        ; AL1: allocation vector for directory, second byte
            .dw     0           ; CKS: directory check vector size (CSV)
            .dw     16          ; OFF: tracks reserved at start of disk (16 = 128KB)

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
alv_drv_a:  .ds 256             ; 2048 blocks
alv_drv_b:  .ds 256             ; 2048 blocks
alv_drv_c:  .ds 256             ; 2048 blocks
alv_drv_d:  .ds 256             ; 2048 blocks
dirbf:      .ds 128             ; directory scratch area
bouncebuf:  .ds 128             ; low memory DMA bounce buffer
postboot_data_end:              ; -- END POST-BOOT BUFFERS --
postboot_data_len = postboot_data_end - postboot_data_start

; -------------------------------------------------------------------------
; START OF MEMORY SHARED WITH POST-BOOT BUFFERS
; -------------------------------------------------------------------------
; rewind the output pointer, overwrite the buffer space with our init code.
. = . - postboot_data_len
init_code_start:

; Found at http://baze.au.com/misc/z80bits.html#2.4
; Divide a 24-bit number by an 8-bit number.
; Input:  E:HL = Dividend, D = Divisor
; Output: E:HL = Quotient, A = Remainder
div24by8:
            xor a
            ld b, #24           ; repeat 24 times
div24bit:
            add hl,hl
            rl  e
            rla
            cp  d
            jr c, div24nextbit  ; jr  c,$+4
            sub d
            inc l
div24nextbit:
            djnz div24bit
            ret

unit_size:
unit_size_lo:   .dw 0
unit_size_hi:   .dw 0

init_unit:
            ; unit number in B, unit_slice_info pointer in IX
            ; unit_slice_info entry is preloaded from ROM with zero LBA, zero slices.

            ; read device type
            ld c, #UNABIOS_BLOCK_GET_TYPE
            call unacheck
            ret nz
            call printdehex
            ex de, hl
            call printdehex

            ; read device size
            push bc                     ; save unit number (B)
            ld c, #UNABIOS_BLOCK_GET_CAPACITY
            ld de, #0
            call unacheck               ; note B is NOT preserved
            pop bc                      ; recover unit number
            ret nz                      ; return if BIOS call failed

            call printdehex
            ex de, hl
            call printdehex
            ex de, hl

            ; sector capacity is in DE:HL, assume we can have the whole disk
            ld (unit_size_lo), hl
            ld (unit_size_hi), de

            ; read MBR table from disk unit
            ld c, #UNABIOS_BLOCK_SETLBA
            ld de, #0                   ; first sector
            ld hl, #0                   ; first sector
            call unacheck
            ret nz

            ld c, #UNABIOS_BLOCK_READ
            ld l, #1                    ; transfer single sector
            ld de, #SECTOR_BUFFER       ; buffer in this bank -- WHERE?
            call unacheck
            ret nz

            ; check for MBR signature
            ld hl, #SECTOR_BUFFER+510
            ld a, (hl)
            cp #0x55
            jr nz, mbrfail
            inc hl
            ld a, (hl)
            cp #0xaa
            jr nz, mbrfail

            ; read primary partition entries
            ld hl, #SECTOR_BUFFER + 446 + 4 ; +446=offset to first partition entry, +4=offset to type byte
            ld b, #4                    ; four partition entries
nextpartition:
            ld de, #4
            ld a, (hl)                  ; read type byte
            add hl, de                  ; LBA address is 4 bytes after partition type
            cp #0x32                    ; look for our partition type (0x32)
            jr z, foundcpmpartiton
            cp #0x05                    ; extended partition (CHS) - ignored for use as "protective partition" purposes.
            jr z, nextslot
            cp #0x0F                    ; extended partition (LBA) - ignored for use as "protective partition" purposes.
            jr z, nextslot
            push bc
            or a                        ; any other non-empty type?
            call nz, foundforeignpartition
            pop bc
nextslot:   ld de, #12                  ; partition entries are 16 bytes total, we already advanced 4
            add hl, de                  ; advance last 12 bytes to next entry
            dec b
            jr nz, nextpartition
mbrfail:
            jr slicecount               ; proceed to compute slice count

foundforeignpartition:
            ; We have found a partition of the wrong type. HL points at start LBA.
            ; Check the first disk sector, it sets a ceiling for the space we can use if no
            ; CP/M partition is defined.
            push hl ; save LBA pointer
            inc hl
            inc hl
            inc hl
            ld de, #unit_size+3
            ex de, hl
            ld b, #4
comp:       ld a, (de)
            cp (hl)
            jr z, compeq        ; equal - check next byte
            jr c, smaller
            jr compdone
            ; jr compdone         ; larger - we're done
compeq:     dec hl
            dec de
            djnz comp
smaller:    ; smaller or equal -- recover the LBA pointer, copy
            pop hl
            push hl
            ld de, #unit_size
            ld bc, #4
            ldir
compdone:   pop hl
            ret

foundcpmpartiton:
            ; we have found a partition of the correct type. HL points at start LBA

            ; store partition LBA offset at IX
            push ix
            pop de
            ld bc, #4
            ldir

            ; copy the unit size for the slice calculation
            ld de, #unit_size
            ld bc, #4
            ldir

slicecount:
            ; there are 0x4100 512-byte sectors per slice. compute unit_size / 0x4100.
            ; we can ignore the low 8 bits and divide the top 24 bits of the length by 0x41.
            ; load into E:HL
            ld hl, (unit_size+1)
            ld a, (unit_size+3)
            ld e, a
            ld d, #0x41                 ; divisor in D
            call div24by8               ; leaves result in E:HL

            ; test if E is non-zero, ie result >= 0x10000 
            ld a, e
            or a
            jr z, gotslices
            ld hl, #0xFFFF              ; maximum number of slices we can handle
gotslices:
            ld 4(ix), l                 ; store slice count
            ld 5(ix), h
            ret

printahex_nopad:
            push bc
            ld c, a  ; copy value
            ; print the top nibble
            rra
            rra
            rra
            rra
            jr z, skiptopnibble
            call printnibble
skiptopnibble:
            ; print the bottom nibble
            ld a, c
            call printnibble
            pop bc
            ret

mallocfail:
            ld de, #mallocfailmsg
            call printstring
            halt

bios_boot:
            ; say hello
            ld de, #bootmsg
            call printstring

            ; report BIOS version
            ld bc, #(UNABIOS_GET_VERSION << 8 | UNABIOS_GETINFO)
            rst #UNABIOS_CALL
            ld h, #0
            ld l, d
            call printhldec
            ld a, #'.'
            call outchar
            ld a, e
            and #0x7f       ; mask test bit
            ld l, a
            call printhldec
            bit 7, e
            jr z, donever
            ld de, #testver
            call printstring
donever:
            ld a, #' '
            call outchar

            ; locate UNA's page in memory
            ld bc, #(UNABIOS_GET_PAGE_NUMBERS << 8 | UNABIOS_GETINFO)
            rst #UNABIOS_CALL
            ld (ubiospage), hl

            ; tell the user about the memory mapping
            push de ; save user page
            ld de, #unamem2msg
            call printstring
            ex de, hl
            call printdehex
            ld de, #unamem3msg
            call printstring
            pop de
            call printdehex
            ld de, #crlf
            call printstring

            ; perform standard CP/M initialisation
            xor a
            ld (iobyte), a
            ld (cdisk), a

            ; allocate sector buffer in UNA's memory bank
            ld c, #UNABIOS_MALLOC
            ld de, #512
            rst #UNABIOS_CALL
            jr nz, mallocfail
            ld (bufadr), hl

            ; allocate buffer for copy of CCP in UNA's memory bank
            ld c, #UNABIOS_MALLOC
            ld de, #l__CPMCCP
            rst #UNABIOS_CALL
            jr nz, mallocfail
            ld (ccpadr), hl

            ; map in UNA memory page
            call una_map_ubios

            ; copy CCP to buffer
            ld hl, #s__CPMCCP
            ld de, (ccpadr)
            ld bc, #l__CPMCCP
            ldir

            ; map in user memory page
            call una_unmap_ubios

            ; patch BOOT system call to point at WBOOT instead.
            ld hl, #bios_wboot
            ld (BOOT+1), hl

            ; read MBR on each disk unit.
            ld ix, #unit_slice_info ; start of unit slice info table
            ld b, #0                ; first unit number

nextunit:
            ld de, #readunitmsg
            call printstring
            ld a, b
            call printahex_nopad
            ld de, #readunitmsg2
            call printstring

            push bc
            call init_unit

            ; zero LBA?
            ld a, 0(ix)
            or 1(ix)
            or 2(ix)
            or 3(ix)
            jr z, notfound

            ld de, #fndpartmsg
            call printstring

            ld a, 3(ix)
            call printahex
            ld a, 2(ix)
            call printahex
            ld a, 1(ix)
            call printahex
            ld a, 0(ix)
            call printahex

            ld de, #fndpartmsg2
            call printstring

            jr prslices

notfound:   ld de, #nopartmsg
            call printstring
            ; fall through
prslices:
            ; print slice count
            ld l, 4(ix)
            ld h, 5(ix)
            call printhldec

            ld de, #slicesmsg
            call printstring

            ; advance to next unit in unit_slice_info table
            ld de, #6
            add ix, de

            ; advance to next unit
            pop bc
            inc b
            ld a, b
            cp #UNITCNT
            jr nz, nextunit

            ; finally, set up for ldir to wipe out the buffers region
            ld hl, #postboot_data_start
            ld de, #postboot_data_start+1
            ld bc, #postboot_data_len-1 ; we'll write the first byte
            ld a, #0x00
            ld (hl), a ; write first byte

            ; continue boot
            jp gocpm_ldir

; print the value in DE in hexdecimal
printdehex:
            ld a, d
            call printahex
            ld a, e
            call printahex
            ret

; print the value in HL in decimal
printhldec:
            ld d, #0        ; flag to skip leading zeros
            ld bc, #-10000
            call dec1
            ld bc, #-1000
            call dec1
            ld bc, #-100
            call dec1
            ld c, #-10
            call dec1
            ld c,b
            ; force printing the last digit for the case HL=0
            ld d, #1

dec1:       ld  a, #'0'-1
dec2:       inc a
            add hl, bc
            jr c, dec2
            sbc hl, bc

            cp #'0'
            jr z, dec4
            ld d, #1      ; yes, we've seen a non-zero digit
dec3:       call outchar
            ret
dec4:       ; it's a zero. have we seen any non-zeroes?
            bit 0, d
            ret z ; no, continue looking
            jr dec3 ; yes, print this digit.

; make UNA BIOS call
; return if no error, with no change to registers
; otherwise print error and return (with all registers except A, BC and the Z flag destroyed)
unacheck:
            rst #UNABIOS_CALL
            ret z ; no error
            push bc ; save error
            ; report it
            ld de, #ioerrmsg    ; no - report error
            call printstring
            ld a, c
            call printahex
            ld de, #crlf
            call printstring
            pop bc
            ld a, c
            or a        ; set Z flag, Z=no error, NZ=error
            ret


; init data/messages

bootmsg:    .ascii "N8VEM UNA BIOS CP/M (Will Sowerbutts, 2014-06-24)\r\n"
            .ascii "CP/M 2.2 Copyright 1979 (c) by Digital Research"
            .ascii "\r\n"
            ; fall through
unamem1msg: .ascii "UNA BIOS "
            .db 0
testver:    .ascii " TEST"
            .db 0
unamem2msg: .ascii "in page 0x"
            .db 0
unamem3msg: .ascii ", user memory in page 0x"
            .db 0


mallocfailmsg: .ascii "UNA malloc failed"
            .db 0

readunitmsg:.ascii "Reading MBR on disk "
            .db 0

readunitmsg2:.ascii " - "
            .db 0

nopartmsg:   .ascii "no CP/M partition found, using LBA 0, "
            .db 0

fndpartmsg: .ascii "CP/M partition at LBA 0x"
            .db 0
fndpartmsg2:.ascii ", "
            .db 0

slicesmsg:  .ascii " slices.\r\n"
            .db 0

; safety check to ensure we do not overflow the available space
init_code_len = (. - init_code_start)
.ifgt (init_code_len - postboot_data_len) ; > 0 ?
; cause an error (.msg, .error not yet supported by sdas which itself is an error)
.msg "Init code/data is too large"
.error 1
.endif
; end of init code and data
; pad buffers to length ---------------------------------------------------
             .ds postboot_data_len - (. - init_code_start)   ; must be last
; -------------------------------------------------------------------------
; END OF MEMORY SHARED WITH POST-BOOT BUFFERS
; -------------------------------------------------------------------------

; safety check to ensure we do not overflow into the UBIOS stub at 0xFF00
cbios_length = . - BOOT
.ifgt cbios_length - (UNABIOS_STUB_START - CBIOS_START) ; > 0 ?
; cause an error (.msg, .error not yet supported by sdas which itself is an error)
.msg "CBIOS is too large"
.error 1
.endif
