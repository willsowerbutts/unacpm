AS=sdasz80
ASOPTS=-fflopz
LD=sdldz80
LDOPTS=-n

CPM = cpm22ccp.rel cpm22bdos.rel cpmbios.rel cpmboot.rel

.SUFFIXES:	# delete default suffixes
.SUFFIXES:	.c .s .ss .inc .rel .ihx .hex

.s.rel:
	$(AS) $(ASOPTS) $*.rel $*.s

all:	cpm.com cpm.ihx cpm.rom

cpm.ihx:	$(CPM)
	$(LD) $(LDOPTS) -f cpm.lnk

cpm.rom:	cpm.ihx
	srec_cat -disable-sequence-warning \
		cpm.ihx -intel -fill 0xff 0 0x8000 -crop 0x000 0x200 \
		cpm.ihx -intel -fill 0xff 0 0x8000 -crop 0xe000 0xff00 -offset -0xde00 \
		-fill 0xff 0x2100 0x8000 \
		-output cpm.rom -binary

cpm.com:	cpm.ihx
	srec_cat -disable-sequence-warning \
		cpm.ihx -intel -crop 0x100 0x200 -offset -0x100 \
		cpm.ihx -intel -crop 0xe000 0xff00 -offset -0xdf00 \
		-output cpm.com -binary

clean:
	rm -f *.ihx *.hex *.rel *.map *.bin *.com *.noi *.rom *.lst
