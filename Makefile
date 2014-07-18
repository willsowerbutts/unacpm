SDCC=sdcc
SDAS=sdasz80
SDLD=sdldz80
ASOPTS=-fflopzws
CCOPTS=--std-sdcc99 --no-std-crt0 -mz80 --opt-code-size --max-allocs-per-node 10000 --Werror
LDOPTS=-n -k /usr/share/sdcc/lib/z80/ -wmx

RUNTIME=cpm22ccp.rel cpm22bdos.rel cpmbios.rel
INIT=bootrom.rel runtime0.rel relocate.rel relocate2.rel cpmimage.rel
INIT+=putchar.rel units.rel bios.rel drives.rel memory.rel config.rel init.rel

.SUFFIXES:	# delete default suffixes
.SUFFIXES:	.c .s .ss .inc .rel .ihx .hex
.PHONY:		clean

%.rel:	%.s
	$(SDAS) $(ASOPTS) $<

%.rel:	%.c
	$(SDCC) $(CCOPTS) -c $<


# all:	cpm.com cpm.ihx cpm.rom
all:	cpm.com cpm.rom cpm.ihx remap.com bootdisk.bin

cpm.ihx:	$(INIT) version.rel
	$(SDLD) $(LDOPTS) -i cpm.ihx -b _CODE=0 -l z80 $(INIT) version.rel

cpm.com:	cpm.ihx
	srec_cat -disable-sequence-warning \
 		cpm.ihx -intel -crop 0x100 0x8000 -offset -0x100 \
 		-output cpm.com -binary

cpm.rom:	cpm.ihx
	srec_cat -disable-sequence-warning \
		cpm.ihx -intel -fill 0xFF 0 0x8000 \
		-output cpm.rom -binary

bootdisk.ihx:	bootdisk.rel
	$(SDLD) $(LDOPTS) -i bootdisk.ihx -b _CODE=0x8000 bootdisk.rel

bootdisk.bin:	bootdisk.ihx
	srec_cat -disable-sequence-warning \
 		bootdisk.ihx -intel -fill 0xFF 0x8000 0x8200 -crop 0x8000 0x8200 -offset -0x8000 \
 		-output bootdisk.bin -binary
	
remap.ihx:	remap.rel
	$(SDLD) $(LDOPTS) -i remap.ihx -b _CODE=0x8000 remap.rel

remap.com:	remap.ihx
	srec_cat -disable-sequence-warning \
 		remap.ihx -intel -crop 0x8000 0x10000 -offset -0x8000 \
 		-output remap.com -binary

clean:
	rm -f *.ihx *.hex *.rel *.map *.bin cpm.com *.noi cpm.rom *.lst cpmimage.c *.asm *.sym remap.com version.s

# Link CP/M at two base addresses so we can derive a relocatable version
cpm-0000.ihx:	$(RUNTIME)
	$(SDLD) $(LDOPTS) -i cpm-0000.ihx -b _CPMCCP=0x0000 -b _CPMBDOS=0x0800 -b _CPMBIOS=0x1600 $(RUNTIME)

cpm-8000.ihx:	$(RUNTIME)
	$(SDLD) $(LDOPTS) -i cpm-8000.ihx -b _CPMCCP=0x8000 -b _CPMBDOS=0x8800 -b _CPMBIOS=0x9600 $(RUNTIME)

cpm-0000.bin:	cpm-0000.ihx
	srec_cat -disable-sequence-warning \
		cpm-0000.ihx -intel \
		-output cpm-0000.bin -binary

cpm-8000.bin:	cpm-8000.ihx
	srec_cat -disable-sequence-warning \
		cpm-8000.ihx -intel -offset -0x8000 \
		-output cpm-8000.bin -binary

cpmimage.c:	cpm-0000.bin cpm-8000.bin
	./mkrelocatable.py cpm-0000.bin cpm-8000.bin cpm-reloc.bin cpmimage.c

version.s:	$(INIT) mkversion.py
	./mkversion.py
