SDCC=sdcc
SDAS=sdasz80
SDLD=sdldz80
ASOPTS=-fflopzws
CCOPTS=--std-sdcc99 --no-std-crt0 -mz80 --opt-code-size --max-allocs-per-node 10000 --Werror
LDOPTS=-n -k /usr/share/sdcc/lib/z80/

RUNTIME=cpm22ccp.rel cpm22bdos.rel cpmbios.rel
INIT=runtime0.rel init.rel relocate.rel cpmimage.rel putchar.rel units.rel bios.rel drives.rel memory.rel

.SUFFIXES:	# delete default suffixes
.SUFFIXES:	.c .s .ss .inc .rel .ihx .hex

%.rel:	%.s
	$(SDAS) $(ASOPTS) $<

%.rel:	%.c
	$(SDCC) $(CCOPTS) -c $<


# all:	cpm.com cpm.ihx cpm.rom
all:	bootcpm.com

bootcpm.ihx:	$(INIT)
	#$(SDLD) $(LDOPTS) -f bootcpm.lnk
	$(SDLD) $(LDOPTS) -mwx -i bootcpm.ihx -b _CODE=0x100 -l z80 $(INIT)

bootcpm.com:	bootcpm.ihx
	srec_cat -disable-sequence-warning \
 		bootcpm.ihx -intel -crop 0x100 0x8000 -offset -0x100 \
 		-output bootcpm.com -binary

# cpm.ihx:	$(CPM)
# 	$(SDLD) $(LDOPTS) -f cpm.lnk
# 
# cpm.rom:	cpm.ihx
# 	srec_cat -disable-sequence-warning \
# 		cpm.ihx -intel -fill 0xff 0 0x8000 -crop 0x000 0x200 \
# 		cpm.ihx -intel -fill 0xff 0 0x8000 -crop 0xe000 0xff00 -offset -0xde00 \
# 		-fill 0xff 0x2100 0x8000 \
# 		-output cpm.rom -binary
# 
# cpm.com:	cpm.ihx
# 	srec_cat -disable-sequence-warning \
# 		cpm.ihx -intel -crop 0x100 0x200 -offset -0x100 \
# 		cpm.ihx -intel -crop 0xe000 0xff00 -offset -0xdf00 \
# 		-output cpm.com -binary

clean:
	rm -f *.ihx *.hex *.rel *.map *.bin bootcpm.com *.noi cpm.rom *.lst cpmimage.c *.asm *.sym

# Link CP/M at two base addresses so we can derive a relocatable version
cpm-0000.ihx:	$(RUNTIME)
	$(SDLD) $(LDOPTS) -f cpm-0000.lnk

cpm-8000.ihx:	$(RUNTIME)
	$(SDLD) $(LDOPTS) -f cpm-8000.lnk

cpm-0000.bin:	cpm-0000.ihx
	srec_cat -disable-sequence-warning \
		cpm-0000.ihx -intel \
		-output cpm-0000.bin -binary

cpm-8000.bin:	cpm-8000.ihx
	srec_cat -disable-sequence-warning \
		cpm-8000.ihx -intel -offset -0x8000 \
		-output cpm-8000.bin -binary

cpmimage.c:	cpm-0000.bin cpm-8000.bin
	./mkrelocatable cpm-0000.bin cpm-8000.bin cpm-reloc.bin cpmimage.c
