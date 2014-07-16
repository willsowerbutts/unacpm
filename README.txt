
         UNA CP/M (c) 2014 William R Sowerbutts <will@sowerbutts.com>
                          http://sowerbutts.com/8bit/

= Introduction =

UNA CP/M is a CP/M 2.2 operating system for computers running UNA BIOS.  

UNA BIOS is a unified BIOS which aims to run on all Z80 and Z180 single board
computer systems from the N8VEM home brew computer project.

UNA CP/M is structured as a two-stage program. The first stage handles the
initialisation of the system and constructs the second (residual) stage in
memory. When the initialisation code has finished it is discarded, with control
passing to the residual second stage which implements CP/M and a minimal CBIOS.

This two-stage approach allows the user to choose a balance between the number
of drives available to CP/M and the size of the transient program area (TPA). 

Once running, the included REMAP program can be used to quickly re-launch UNA
CP/M with a different drive mapping.

This version of UNA CP/M includes only basic support for character I/O 
devices. The CP/M "I/O byte" is ignored. All console input and output are 
handled by UNA serial device 0.

UNA CP/M's CBIOS is based in part on the RomWBW CBIOS by Wayne Warthen and 
Andrew Lynch.


= Drives, Units, Disks, Partitions and Slices =

UNA CP/M provides a flexible mapping from CP/M drives to the underlying storage
devices. The mapping of CP/M drives to disks and slices can be controlled by
the user as described later in this document.

CP/M's filesystem is based around the concept of "drives" which it labels as
A:, B:, C: etcetera. Each drive is a separate file system.

UNA BIOS presents each mass storage device (disk) in the system available as 
a separate "unit". UNA BIOS uses unit numbers to refer to these. UNA CP/M 
gives each disk a name, for example "IDE0" and "IDE1" are the first two IDE 
disks in the system, while "SD0" is the first SD card.

Disks larger than approximately 8MB can hold multiple CP/M filesystems. These 
disks are divided into a series of "slices", with each slice holding a 
separate filesystem. Multiple CP/M drives may be mapped to different slices 
on a single disk. The slices on each disk are enumerated 0, 1, 2 etcetera.  
Each slice is exactly 8,320KB in length, with the first 128KB reserved to 
hold system-specific data (for example, the data required to boot from the 
disk).

Previous CP/M systems for N8VEM, including RomWBW, store the slices starting 
at the LBA 0 (ie, the first sector) and extending to cover the entire disk.  
This can be a problem if you wish to store other filesystems on the disk. UNA 
CP/M supports disks that optionally use a PC-style MBR partition table.

UNA CP/M will read the four primary partition entries from the MBR and use 
these to decide where to store its data on the disk.

If UNA CP/M finds a partition of type 0x32, it will use this partition to 
store all CP/M slices. The layout of the slices is identical but they are 
accessed starting from the first block of the partition rather than the first 
block of the disk.

If UNA CP/M finds a partition of type 0x05 or 0x0F it will ignore it. These 
partition types can therefore be used to create "protective" areas, ie to 
mark the space as being in use and prevent other systems from trying to use
it.

If UNA CP/M finds partitions of any other type it will regard them as being 
in use by some foreign operating system and will avoid using that space 
entirely. This ensures that CP/M does not overlay slices over another 
operating system's data.

If that all sounds complex, don't panic! Here are the common scenarios:

You have a disk that you use with RomWBW, containing no MBR partition table: 
You don't need to do anything, it will be compatible with UNA CP/M. UNA will 
store slices starting from LBA 0 across the entire disk.

You have a blank disk that you want to use with UNA CP/M and optionally other 
operating systems: Write an MBR partition table to it, put a partition of 
type 0x32 anywhere on the disk. UNA CP/M will exclusively use that partition.  
If you allocate space to other operating systems, UNA CP/M will never use 
that space.

You have a disk that you use with RomWBW which contains an MBR partition 
table: UNA CP/M will use all the space from the start of the disk up to the 
start of the first "foreign" partition. If you've left unpartitioned space at 
the start of the disk, it will use this. If you've created a "protective" 
partition to stop other operating systems writing to this space, make sure it 
is type 0x05 or 0x0F so that UNA CP/M ignores it rather than regarding it as 
"foreign".

You have a disk that you use with RomWBW and you want to use a type 0x32 
partition to contain your data: This is a little more complex as the RomWBW 
slices start at LBA 0 but you cannot create a partition that includes LBA 0.  
You need to copy the slices off onto another disk, create the partition, and 
then copy the slices back into the partition. Under Linux you would do:

 $ dd if=/dev/sdx bs=8320k count=16 of=/tmp/cpmslices
 $ fdisk /dev/sdx        # create new partition, type 0x32, for UNA CP/M
 $ dd if=/tmp/cpmslices bs=8320k of=/dev/sdx1

These commands assume you have used 16 slices on disk /dev/sdx and that your 
new UNA CP/M partition is the first on the disk.


= Running UNA CP/M =

There are several ways to boot UNA CP/M. They all require UNA BIOS to be loaded
and running already.

The standard way to run UNA CP/M is from ROM. The 32KB CPM.ROM file becomes
part of the ROM, normally immediately after the 64KB UNA BIOS ROM. UNA BIOS
will boot CP/M directly from this ROM page when you type "R" at the boot
prompt. 

Once booted from ROM, you can reconfigure the drive mapping using the 
"REMAP.COM" program. This small program finds the copy of UNA CP/M in ROM  
and invokes it again. Ideally one would keep a copy of "REMAP.COM" on the ROM 
disk for this purpose.

Another way to load UNA CP/M is from the "CPM.COM" file. "CPM.COM" is simply 
a copy of "CPM.ROM" with the first 256 bytes removed and without padding to 
fill a 32KB ROM page. CPM.COM can be run from an existing CP/M system, 
providing UNA BIOS is present in the system. This is a good way to test new 
releases of UNA CP/M before writing them to ROM.

The final way to run UNA CP/M is to boot it from disk. A small bootstrap 
program is distributed with UNA CP/M for this purpose, named "BOOTDISK.BIN".  
Instructions for making a boot disk are included below.


= Command Line options =

When you run UNA CP/M you can specify options on the command line. With the
"REMAP.COM" (and "CPM.COM") programs, simply type the options after the program
name. At the UNA BIOS boot prompt you may type the options after the boot unit
number.

You may specify up to 16 storage devices to be mapped to the CP/M drives. Each
device should be specified as the disk name followed by an optional slice
number. The slice number is delimited from the disk name by a colon or period
character (":" or "."). If no slice number is specified, slice 0 is assumed.

For example, at the UNA BIOS "boot unit number" prompt, you might type:

   R RAM0 ROM0 IDE0.2

This will boot UNA CP/M from ROM with A: mapped to the RAM disk, B: mapped to
the ROM disk, and and C: mapped to slice 2 on disk IDE0.

Once booted, you might then type (at the "A0>" prompt):

   B:REMAP RAM0 IDE0 IDE0.3

This would load REMAP.COM from the ROM disk (B:) and restart CP/M with A:
mapped to the RAM disk, while B: and C: are mapped to slices 0 and 3
(respectively) on disk IDE0.

If no mapping is specified on the command line, UNA CP/M will try to load a
saved configuration from disk. If no configuration is found it will default to
mapping a drive to the first slice on every disk.

UNA stores its configuration in the system track of slice 0 on each disk, in
the second 512-byte sector of the slice. Configuration can therefore only be
stored on sliced disks. If multiple disks with stored configurations are found,
priority is given in the following order:

 - The boot disk
 - The first disk with a CP/M partition (type 0x32)
 - The first disk with a stored configuration

The following command line options can be used to manage stored configurations:

  /SAVE -- save the configuration specified on the command line to disk. By
default the previous saved configuration is overwritten. If no configuration
was previously saved, you must use the /CONFDISK option to tell UNA CP/M which
disk to write to.

  /CONFDISK:<disk> -- tell CP/M which disk to use for configuration. This can be
used to override the autoselection on loading, or to specify the configuration
storage device when using /SAVE for the first time.

  /CONFERASE:<disk> -- erase the stored configuration from the specified disk.

For example, to write a configuration to disk for the first time:

  REMAP RAM0 ROM0 IDE0 IDE0.1 SD0 SD0.1 /SAVE /CONFDISK:IDE0

After the first time, the "/CONFDISK" option may be omitted:

  REMAP RAM0 ROM0 /SAVE

By default the CP/M system is loaded into memory at a page-aligned address.
This is for compatability with CP/M applications which talk directly to the
CBIOS, many of which assume the CBIOS is page aligned. If your application does
not make this assumption and can use a slightly larger TPA, the "/BYTE" command
line option will load the residual at a higher byte-aligned address. This is
not recommended.


= Making a bootable disk =

BOOTDISK.BIN must be loaded to sector 0 of the disk, and a copy of CPM.ROM 
must be loaded to sectors 2 onwards. Note that sector 1 is not used.  

If you have an MBR partition table on the disk you must merge it with 
BOOTDISK.BIN;

  $ dd if=bootdisk.bin bs=1 count=320 of=/dev/sdx

If you do not you can just overwrite the entire first sector;

  $ dd if=bootdisk.bin bs=512 count=1 of=/dev/sdx

You can then write the CPM.ROM file to the appropriate sectors;

  $ dd if=cpm.rom bs=512 count=64 seek=2 of=/dev/sdx

Note that this overwrites the first 33KB of the disk; it is not uncommon for 
the first partition to start at around sector 63 so please take care not to 
overwrite it. BOOTDISK.BIN will always load 32KB from disk but the end of 
CPM.ROM is actually unused, so if you have this problem you can simply avoid 
copying the unused portion;

  $ dd if=cpm.rom bs=512 count=50 seek=2 of=/dev/sdx

To determine the minimum amount of CPM.ROM you must copy, take the size of 
CPM.COM and add 256 bytes. 

You can now boot this disk by specifying the unit number at the UNA BIOS boot 
prompt. You may optionally follow the unit number with a command line 
specifying the desired drive mapping.


= Bugs =

Both UNA BIOS and UNA CP/M are in development. Please report any bugs you find
to the authors. My email address is will@sowerbutts.com.


= License =

UNA CP/M is licensed under the The GNU General Public License version 3 (see
included "LICENSE.txt" file). 

UNA CP/M is provided with NO WARRANTY. In no event will the author be liable 
for any damages. Use of this program is at your own risk. May cause short 
term memory loss, or worse, short term memory loss.
