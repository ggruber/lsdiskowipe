package lsdiskowipe::getSlotInfo;
use strict;
use warnings;
use lsdiskowipe::readSmartData;
use Data::Dumper;

sub sortDiskNames {
    my $deltal = length( $a ) - length( $b );
    return ($deltal ? $deltal : $a cmp $b);
}

sub getSlotInfo {
    my $smart = $_[0];
    my $disk;
    my $controller;
    my $controllertype = 0;
    my %controllerInfo;
    my %controllerMgmt = (
	"ahci"         => "sltinf_none",
	"ata_piix"     => "sltinf_none",
	"nvme"         => "sltinf_none",
	"uas"          => "sltinf_none",
	"usb-storage"  => "sltinf_none",
	"3w-9xxx"      => "unimplemented",   # twcli
	"3w-sas"       => "unimplemented",   # twcli
	"mptsas"       => "sltinf_lsiutil",  # lsiutil or lsimega or megacli?
	"mpt2sas"      => "sltinf_sas23ircu",
	"mpt3sas"      => "sltinf_sas23ircu",
	"megaraid_sas" => "sltinf_storcli",  # storcli
	"aacraid"      => "unimplemented",   # arcconf
    );

    # first: which controllers do we have
    foreach $disk ( sort sortDiskNames keys %$smart ) {
	$controllerInfo{$smart->{$disk}{driver}} .= $controllerInfo{$smart->{$disk}{driver}} ? ", $disk" : $disk;
    }
    foreach $controller ( keys %controllerInfo ) {
	print "controller: $controller -> disks: $controllerInfo{$controller}\n" if $main::debug;
	$controllertype++;	# simply enumerate
        print "get slot info from $controllerMgmt{$controller}\n" if $main::debug;
	my $getInfo = "$controllerMgmt{$controller}(\"$controller\", \"$controllertype\", \$smart, \"$controllerInfo{$controller}\")";
	print "getInfo command: $getInfo\n" if $main::debug;
	eval $getInfo;
	next if ( (not defined $controllerMgmt{$controller}) or $controllerMgmt{$controller} =~ /none|unimplemented/i );
	$main::SlotInfoAvailable = 1;
    }
}

sub sltinf_none {
    my $ctrlmodule = $_[0];
    my $controllertype = $_[1];
    my $smart = $_[2];
    my $disklist = $_[3];

    print "Controllertype: $ctrlmodule\n" if $main::debug; 
    my @disklistA = split ( /, /, $disklist);
    my $disk;

    foreach $disk ( @disklistA ) {
	$smart->{$disk}{slotinfo} = "$controllertype" . ":::";
    }
}
sub sltinf_lsiutil {
    my $ctrlmodule = $_[0];
    my $controllertype = $_[1];
    my $smart = $_[2];
    my $disklist = $_[3];

    print "Controllertype: $ctrlmodule\n" if $main::debug; 
    my @disklistA = split ( /, /, $disklist);
    my $infprog = "lsiutil";
    my $disk;

# initialise
    foreach $disk ( @disklistA ) {
	$smart->{$disk}{slotinfo} = "$controllertype" . ":::";
    }

    if ( not `sh -c "which $infprog"` ) {
	print "ERROR: required program \"$infprog\" not found, -> install it to continue. Aborting!\n";
	exit 2;
    }

    # get controller count
    my @controlleridxs;
    my $controller;

    print "getting # of installed controllers from $infprog\n"  if $main::verbose;
    open (PROGOUT, "echo 0 | $infprog |" || die "getting controllercount from $infprog failed");
# expected output
# 
# LSI Logic MPT Configuration Utility, Version 1.56, March 19, 2008
# 
# 1 MPT Port found
# 
#      Port Name         Chip Vendor/Type/Rev    MPT Rev  Firmware Rev  IOC
#  1.  /proc/mpt/ioc0    LSI Logic SAS1068E B3     105      00192f00     0
# 
# Select a device:  [1-1 or 0 to quit] 
    while (<PROGOUT>) {
	chomp;
	if ($_ =~ /^\s+(\d+)\.\s+\/proc\/mpt/) {
	    push (@controlleridxs, $1)
	}
    }
    close (PROGOUT);
    print "$infprog Controllers found ( " . scalar @controlleridxs ." ), index: @controlleridxs\n"  if $main::verbose;

    # get diskidentifier per slot
    my $inDiskList = 0;

    foreach $controller ( @controlleridxs ) {
	print "$infprog: reading controller $controller\n" if $main::verbose;
	open (PROGOUT, "$infprog -p $controller -a 42,0,0 |" || die "getting infos from $infprog controller #$controller failed");
# get info for all disks

# expected output
#
# this is only a JBOD configuration
#
# # lsiutil -p 1 -a 42,0,0
# 
# LSI Logic MPT Configuration Utility, Version 1.56, March 19, 2008
# 
# 1 MPT Port found
# 
#      Port Name         Chip Vendor/Type/Rev    MPT Rev  Firmware Rev  IOC
#  1.  /proc/mpt/ioc0    LSI Logic SAS1068E B3     105      00192f00     0
# 
# Main menu, select an option:  [1-99 or e/p/w or 0 to quit] 42
# 
# /proc/mpt/ioc0 is SCSI host 2
# 
#  B___T___L  Type       Operating System Device Name
#  0   0   0  Disk       /dev/sdc    [2:0:0:0]
#  0   1   0  Disk       /dev/sdd    [2:0:1:0]
#  0   2   0  Disk       /dev/sde    [2:0:2:0]
#  0   3   0  Disk       /dev/sdf    [2:0:3:0]
#  0   4   0  Disk       /dev/sdg    [2:0:4:0]
#  0   5   0  Disk       /dev/sdh    [2:0:5:0]
#  0   6   0  Disk       /dev/sdi    [2:0:6:0]
#  0   7   0  Disk       /dev/sdj    [2:0:7:0]
#  0   8   0  EnclServ
# 
# Main menu, select an option:  [1-99 or e/p/w or 0 to quit] 0
# 
	while (<PROGOUT>) {
            print $_ if $main::Debug;
	    chomp;
	    next if ( $inDiskList == 0 and $_ !~ /B___T___L/ );
	    if ( $_ =~ /B___T___L/i ) {	# Board aka Controller#, Target aka Slot, LUN
		$inDiskList = 1;
	    }
	    elsif ( /^\s+(\d+)\s+(\d+)\s+(\d+)\s+Disk\s+\/dev\/(\S+)\s+/i ) {	#
		print "Board: $1 Target: $2 LUN: $3 Disk: $4\n" if $main::verbose;
		$smart->{$4}{slotinfo} = "$controllertype:$controller:$1:$2";
	    }
	}
    }
}
sub sltinf_sas23ircu {
    my $ctrlmodule = $_[0];
    my $controllertype = $_[1];
    my $smart = $_[2];
    my $disklist = $_[3];

    print "Controllertype: $ctrlmodule\n" if $main::debug; 
    my $infprog = $ctrlmodule eq "mpt2sas" ? "sas2ircu" : "sas3ircu";	# expected to be found in path
    my @disklistA = split ( /, /, $disklist);
    my $diskidentifier;
    my %diskidenthash;
    my $disk;

    my $inHD;
    my $complete;
    my $enclosure;
    my $slot;
    my $modell;
    my $serial;
    my $currentdiskid;

    print Dumper (%$smart) if $main::Debug;
    print Dumper (@disklistA) if $main::Debug;
    # build a hash of $smart->{$disk}{diskIdentifier} => disk
    foreach $disk ( @disklistA ) {
	$smart->{$disk}{vendor} = "" unless $smart->{$disk}{vendor};
	$smart->{$disk}{devModel} = "" unless $smart->{$disk}{devModel};
	$smart->{$disk}{serial} = "" unless $smart->{$disk}{serial};
	if ( $smart->{$disk}{vendor} eq "" or $smart->{$disk}{devModel} eq "" or $smart->{$disk}{serial} eq "" ) {
	    # Warning here, but will eventually be fixed in consolidateDrives
	    print "Warning: disk $disk no vendor ($smart->{$disk}{vendor}) or no modell ($smart->{$disk}{devModel})" .
		  " or no serial ($smart->{$disk}{serial})\n" if $main::debug;
	}
	# $diskidentifier = $smart->{$disk}{vendor}.$smart->{$disk}{devModel}.$smart->{$disk}{serial};	# drop vendor, as SATA disks don't show one
	$serial = $smart->{$disk}{serial};
	$serial =~ s/-//g;	# drop '-' characters from serial number as controller strips this when reporting serial
	$diskidentifier = "$smart->{$disk}{devModel}.$serial";
	print "disk: $disk diskindentifier: $diskidentifier\n" if $main::debug;
	$diskidenthash{$diskidentifier} .= $diskidenthash{$diskidentifier} ? ", $disk" : $disk;
    }
    print Dumper(%diskidenthash) if $main::Debug;
    # get controller count
    my @controlleridxs;
    my $controller;

    if ( not `sh -c "which $infprog"` ) {
	print "ERROR: required program \"$infprog\" not found, -> install it to continue. Aborting!\n";
	exit 2;
    }

    print "getting # of installed controllers from $infprog\n"  if $main::verbose;
    open (PROGOUT, "$infprog LIST |" || die "getting controllercount from $infprog failed");
# expected output
# LSI Corporation SAS2 IR Configuration Utility.
# Version 16.00.00.00 (2013.03.01)
# Copyright (c) 2009-2013 LSI Corporation. All rights reserved.
#
#
#          Adapter      Vendor  Device                       SubSys  SubSys
#  Index    Type          ID      ID    Pci Address          Ven ID  Dev ID
#  -----  ------------  ------  ------  -----------------    ------  ------
#    0     SAS2008     1000h    72h   00h:07h:00h:00h      1028h   1f1ch
#
#          Adapter      Vendor  Device                       SubSys  SubSys
#  Index    Type          ID      ID    Pci Address          Ven ID  Dev ID
#  -----  ------------  ------  ------  -----------------    ------  ------
#    1     SAS2008     1000h    72h   00h:03h:00h:00h      1028h   1f1ch
# SAS2IRCU: Utility Completed Successfully.
    #
    while (<PROGOUT>) {
	chomp;
	if ($_ =~ /^\s+(\d+)/) {
	    push (@controlleridxs, $1)
	}
    }
    close (PROGOUT);
    print "$infprog Controllers found ( " . scalar @controlleridxs ." ), index: @controlleridxs\n"  if $main::verbose;
    # get diskidentifier per slot
    foreach $controller ( @controlleridxs ) {
	print "$infprog: reading controller $controller\n" if $main::verbose;
	open (PROGOUT, "$infprog $controller DISPLAY |" || die "getting infos from $infprog controller #$controller failed");
# expected output

## # sas2ircu 0 DISPLAY
## LSI Corporation SAS2 IR Configuration Utility.
## Version 16.00.00.00 (2013.03.01)
## Copyright (c) 2009-2013 LSI Corporation. All rights reserved.
## 
## Read configuration has been initiated for controller 0
## ------------------------------------------------------------------------
## Controller information
## ------------------------------------------------------------------------
##   Controller type                         : SAS2008
##   BIOS version                            : 7.39.02.00
##   Firmware version                        : 20.00.07.00
##   Channel description                     : 1 Serial Attached SCSI
##   Initiator ID                            : 0
##   Maximum physical devices                : 255
##   Concurrent commands supported           : 3432
##   Slot                                    : 6
##   Segment                                 : 0
##   Bus                                     : 7
##   Device                                  : 0
##   Function                                : 0
##   RAID Support                            : No
## ------------------------------------------------------------------------
## IR Volume information
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## Physical device information
## ------------------------------------------------------------------------
## Initiator at ID #0
## 
## Device is a Hard disk
##   Enclosure #                             : 1
##   Slot #                                  : 0
##   SAS Address                             : 5000c50-0-4c08-4e25
##   State                                   : Ready (RDY)
##   Size (in MB)/(in sectors)               : 572325/1172123567
##   Manufacturer                            : SEAGATE
##   Model Number                            : ST3600057SS
##   Firmware Revision                       : 000B
##   Serial No                               : 6SL3NF2J
##   GUID                                    : 5000c5004c084e27
##   Protocol                                : SAS
##   Drive Type                              : SAS_HDD
## 
## ~~~~
## Device is a Hard disk
##   Enclosure #                             : 1
##   Slot #                                  : 6
##   SAS Address                             : 4433221-1-0500-0000
##   State                                   : Ready (RDY)
##   Size (in MB)/(in sectors)               : 2861588/5860533167
##   Manufacturer                            : ATA
##   Model Number                            : ST3000VX000-1ES1
##   Firmware Revision                       : CV26
##   Serial No                               : Z501575F
##   GUID                                    : 5000c5007abbc664
##   Protocol                                : SATA
##   Drive Type                              : SATA_HDD
## 
## ~~~~
## Device is a Hard disk
##   Enclosure #                             : 2
##   Slot #                                  : 18
##   SAS Address                             : 500056b-3-6789-abd2
##   State                                   : Ready (RDY)
##   Size (in MB)/(in sectors)               : 476940/976773167
##   Manufacturer                            : ATA
##   Model Number                            : CT500MX500SSD1
##   Firmware Revision                       : 043
##   Serial No                               : 2205E604CA7C
##   GUID                                    : 500a0751e604ca7c
##   Protocol                                : SATA
##   Drive Type                              : SATA_SSD
## 
## ~~~~
## ------------------------------------------------------------------------
## Enclosure information
## ------------------------------------------------------------------------
##   Enclosure#                              : 1
##   Logical ID                              : 5782bcb0:24cd7600
##   Numslots                                : 9
##   StartSlot                               : 0
## ------------------------------------------------------------------------
## SAS2IRCU: Command DISPLAY Completed Successfully.
## SAS2IRCU: Utility Completed Successfully.
##

# or
## LSI Corporation SAS2 IR Configuration Utility.
## Version 13.00.00.00 (2012.02.17)
## Copyright (c) 2009-2012 LSI Corporation. All rights reserved.
##
## Read configuration has been initiated for controller 0
## ------------------------------------------------------------------------
## Controller information
## ------------------------------------------------------------------------
##   Controller type                         : SAS2008
##   BIOS version                            : 7.11.01.00
##   Firmware version                        : 7.15.04.00
##   Channel description                     : 1 Serial Attached SCSI
##   Initiator ID                            : 0
##   Maximum physical devices                : 39
##   Concurrent commands supported           : 2607
##   Slot                                    : 2
##   Segment                                 : 0
##   Bus                                     : 8
##   Device                                  : 0
##   Function                                : 0
##   RAID Support                            : Yes
## ------------------------------------------------------------------------
## IR Volume information
## ------------------------------------------------------------------------
## IR volume 1
##   Volume ID                               : 79
##   Status of volume                        : Okay (OKY)
##   Volume wwid                             : 09a9fa55ec971d19
##   RAID level                              : RAID1
##   Size (in MB)                            : 285568
##   Physical hard disks                     :
##   PHY[0] Enclosure#/Slot#                 : 1:0
##   PHY[1] Enclosure#/Slot#                 : 1:1
## ------------------------------------------------------------------------
## Physical device information
## ------------------------------------------------------------------------
## Initiator at ID #0
## Device is a Hard disk
##   Enclosure #                             : 1
##   Slot #                                  : 0
##   SAS Address                             : 5000c50-0-1769-4b89
##   State                                   : Optimal (OPT)
##   Size (in MB)/(in sectors)               : 286102/585937499
##   Manufacturer                            : SEAGATE
##   Model Number                            : ST3300656SS
##   Firmware Revision                       : HS11
##   Serial No                               : 3QP2M7XR
##   GUID                                    : 5000c50017694b8b
##   Protocol                                : SAS
##   Drive Type                              : SAS_HDD
##
## ~~~~
## Device is a Enclosure services device
##   Enclosure #                             : 1
##   Slot #                                  : 9
##   SAS Address                             : 5882b0b-0-24cd-7600
##   State                                   : Standby (SBY)
##   Manufacturer                            : DP
##   Model Number                            : BACKPLANE
##   Firmware Revision                       : 1.07
##   Serial No                               : 127017A
##   GUID                                    : N/A
##   Protocol                                : SAS
##   Drive Type                              : SAS_HDD
## ------------------------------------------------------------------------
## Enclosure information
## ------------------------------------------------------------------------
##   Enclosure#                              : 1
##   Logical ID                              : 5782bcb0:24cd7600
##   Numslots                                : 9
##   StartSlot                               : 0
## ------------------------------------------------------------------------
## SAS2IRCU: Command DISPLAY Completed Successfully.
## SAS2IRCU: Utility Completed Successfully.
##
	$inHD = 0;
	$complete = 0;
	$enclosure = "";
	$slot = "";
	$modell = "";
	$serial = "";

	while (<PROGOUT>) {
            print $_ if $main::Debug;
	    chomp;
	    next if ( $inHD == 0 and $_ !~ /Device is a Hard Disk/i );
	    if ( $_ =~ /Device is a Hard Disk/i ) {
		$inHD = 1;
	    }
	    elsif ( /^\s+Drive Type\s+:/i ) {	# last line for a disk
		$inHD = 0;
		$enclosure = "";
		$slot = "";
		$modell = "";
		$serial = "";
		if ( $complete == 0 ) {
			print "incomplete information for disk: ";
			print "encl: $enclosure, slot: $slot, modell: $modell, serial: $serial\n";
		}
		$complete = 0;
	    }
	    elsif ( /^\s+Enclosure #\s+:\s+(\d+)/i ) {
		$enclosure = $1;
	    }
	    elsif ( /^\s+Slot #\s+:\s+(\d+)/i ) {
		$slot = $1;
	    }
	    elsif ( /^\s+Model Number\s+:\s+(\S+.*)$/i ) {
		$modell = $1;
	    }
	    elsif ( /^\s+Serial No\s+:\s+(\S+.*)$/i ) {
		$serial = $1;
	    }
	    elsif ( $complete == 0 and length $enclosure and length $slot and length $modell and length $serial  ) {
		# we have all infos for a disk we look for
		$complete = 1;
    # match against diskidentifier hash, set Slot attribute per disk
		print "controller: $controller, encl: $enclosure, slot: $slot, modell: $modell, serial: $serial\n" if $main::debug;
		$modell =~ s/\s*$//;
		$modell =~ s/^\S+\s+//i if $modell =~ /\s/;	# drop Manufacturer as in "WDC WD2000F9YZ-0" or "Hitachi HUA72302"
		$serial =~ s/\s*$//;
		foreach $currentdiskid ( keys %diskidenthash ) {
		    if ( $currentdiskid =~ /$modell.*\.$serial/i ) {
			print "found $diskidenthash{$currentdiskid} at T:C:E:S: $controllertype:$controller:$enclosure:$slot\n" if $main::debug;
			foreach my $curdisk ( split ( /, /, $diskidenthash{$currentdiskid} ) ) { 
			    # consider multipathing
			    $smart->{$curdisk}{slotinfo} .= $smart->{$curdisk}{slotinfo} ? ", $controllertype:$controller:$enclosure:$slot" : "$controllertype:$controller:$enclosure:$slot";
			}
		    } else {
			my $tempmodell;
			my $tempserial;
			($tempmodell, $tempserial) = split (/\./, $currentdiskid);
			if ( "$modell\.$serial" =~ /$tempmodell.*\.$tempserial/i ) {
			    print "altfound $diskidenthash{$currentdiskid} at T:C:E:S: $controllertype:$controller:$enclosure:$slot\n" if $main::debug;
			    foreach my $curdisk ( split ( /, /, $diskidenthash{$currentdiskid} ) ) {
				# consider multipathing
				$smart->{$curdisk}{slotinfo} .= $smart->{$curdisk}{slotinfo} ? ", $controllertype:$controller:$enclosure:$slot" : "$controllertype:$controller:$enclosure:$slot";
			    }
			}
		    }
		}
	    }
	        
	}
	close (PROGOUT);
    }
}

sub sltinf_storcli {
    my $ctrlmodule = $_[0];
    my $controllertype = $_[1];
    my $smart = $_[2];
    my $disklist = $_[3];

    print "Controllertype: $ctrlmodule\n" if $main::debug; 
    my $infprog = "storcli";
    my @disklistA = split ( /, /, $disklist);
    my $disk;

    my $diskidentifier;
    my %diskidenthash;

    my $inHD;
    my $complete;
    my $enclosure;
    my $slot;
    my $modell;
    my $serial;
    my $currentdiskid;

    print Dumper (%$smart) if $main::Debug;
    print Dumper (@disklistA) if $main::Debug;
    # build a hash of $smart->{$disk}{diskIdentifier} => disk
    foreach $disk ( @disklistA ) {
	$smart->{$disk}{vendor} = "" unless $smart->{$disk}{vendor};
	$smart->{$disk}{devModel} = "" unless $smart->{$disk}{devModel};
	$smart->{$disk}{serial} = "" unless $smart->{$disk}{serial};
	if ( $smart->{$disk}{vendor} eq "" or $smart->{$disk}{devModel} eq "" or $smart->{$disk}{serial} eq "" ) {
	    print "Warning: disk $disk no vendor ( $smart->{$disk}{vendor} ) or 
	           no modell ( $smart->{$disk}{devModel} or no serial ( $smart->{$disk}{serial}\n";
	}
	# $diskidentifier = $smart->{$disk}{vendor}.$smart->{$disk}{devModel}.$smart->{$disk}{serial};	# drop vendor, as SATA disks don't show one
	$serial = $smart->{$disk}{serial};
	$serial =~ s/-//g;	# drop '-' characters from serial number as controller strips this when reporting serial
	$diskidentifier = "$smart->{$disk}{devModel}.$serial";
	print "disk: $disk diskindentifier: $diskidentifier\n" if $main::debug;
	$diskidenthash{$diskidentifier} .= $diskidenthash{$diskidentifier} ? ", $disk" : $disk;
    }
    print Dumper(%diskidenthash) if $main::Debug;
    # get controller count
    my $controllercnt;
    my @controlleridxs;
    my $controllerId;

    if ( not `sh -c "which $infprog"` ) {
	print "ERROR: required program \"$infprog\" not found, -> install it to continue. Aborting!\n";
	exit 2;
    }
    print "getting # of installed controllers from $infprog\n"  if $main::verbose;
    open (PROGOUT, "$infprog show ctrlcount |" || die "getting controllercount from $infprog failed");
    while (<PROGOUT>) {
	chomp;
	if ($_ =~ /Controller Count = (\d+)/) {
	    $controllercnt = $1
	}
    }
    close (PROGOUT);
    for ( my $i = 0; $i < $controllercnt; $i++ ) {
	push ( @controlleridxs, $i );
    }
    print "$infprog: Controllers found ( " . scalar @controlleridxs ." ), index: @controlleridxs\n"  if $main::debug;
    foreach $controllerId ( @controlleridxs ) {

	my @encloseidxs = ();
	my $enclosureId;

	print "$infprog: reading controller $controllerId\n" if $main::verbose;
	# get enclosure info
	open (PROGOUT, "$infprog /c$controllerId/eall show |" || die "getting enclosure infos from $infprog controller #$controllerId failed");
# sample output
## # storcli /c0/eall show  | less
## CLI Version = 007.1623.0000.0000 May 17, 2021
## Operating system = Linux 6.5.11-7-pve
## Controller = 0
## Status = Success
## Description = None
## 
## 
## Properties :
## ==========
## 
## ----------------------------------------------------------------------------
## EID State Slots PD PS Fans TSs Alms SIM Port#      ProdID    VendorSpecific
## ----------------------------------------------------------------------------
##  32 OK       16  8  0    0   0    0   1 00 & 00 x8 BP13G+EXP
## ----------------------------------------------------------------------------
## 
## EID=Enclosure Device ID | PD=Physical drive count | PS=Power Supply count
## TSs=Temperature sensor count | Alms=Alarm count | SIM=SIM Count | ProdID=Product ID
## 

	while (<PROGOUT>) {
	    chomp;
	    if ( $_ =~ /^\s+(\d+)\s+/ ) {
		push ( @encloseidxs, $1 );
	    }
	}
	close (PROGOUT);
	# get phys disk info per enclosure
	while ( $enclosureId = pop ( @encloseidxs ) ) {
	    print "$infprog: reading disk info for controller $controllerId enclosure $enclosureId\n" if $main::verbose;
	    open (PROGOUT, "$infprog /c$controllerId/e$enclosureId/sall show all |" || die "getting disk infos from $infprog controller #$controllerId enclosure $enclosureId failed");
# sample output
## CLI Version = 007.1623.0000.0000 May 17, 2021
## Operating system = Linux 6.5.11-7-pve
## Controller = 0
## Status = Success
## Description = Show Drive Information Succeeded.
## 
## 
## Drive /c0/e32/s0 :
## ================
## 
## ----------------------------------------------------------------------------
## EID:Slt DID State DG       Size Intf Med SED PI SeSz Model          Sp Type
## ----------------------------------------------------------------------------
## 32:0      0 JBOD  -  111.790 GB SATA SSD N   N  512B SSDSC2BB120G7R U  -
## ----------------------------------------------------------------------------
## 
## EID=Enclosure Device ID|Slt=Slot No|DID=Device ID|DG=DriveGroup
## DHS=Dedicated Hot Spare|UGood=Unconfigured Good|GHS=Global Hotspare
## UBad=Unconfigured Bad|Sntze=Sanitize|Onln=Online|Offln=Offline|Intf=Interface
## Med=Media Type|SED=Self Encryptive Drive|PI=Protection Info
## SeSz=Sector Size|Sp=Spun|U=Up|D=Down|T=Transition|F=Foreign
## UGUnsp=UGood Unsupported|UGShld=UGood shielded|HSPShld=Hotspare shielded
## CFShld=Configured shielded|Cpybck=CopyBack|CBShld=Copyback Shielded
## UBUnsp=UBad Unsupported|Rbld=Rebuild
## 
## 
## Drive /c0/e32/s0 - Detailed Information :
## =======================================
## 
## Drive /c0/e32/s0 State :
## ======================
## Shield Counter = 0
## Media Error Count = 0
## Other Error Count = 5156
## Drive Temperature =  24C (75.20 F)
## Predictive Failure Count = 0
## S.M.A.R.T alert flagged by drive = No
## 
## 
## Drive /c0/e32/s0 Device attributes :
## ==================================
## SN =   PHDV808506RR150MGN
## Manufacturer Id = ATA
## Model Number = SSDSC2BB120G7R
## NAND Vendor = NA
## WWN = 55CD2E414F1CC936
## Firmware Revision = N201DL43
## Raw size = 111.790 GB [0xdf94bb0 Sectors]
## Coerced size = 111.250 GB [0xde80000 Sectors]
## Non Coerced size = 111.290 GB [0xde94bb0 Sectors]
## Device Speed = 6.0Gb/s
## Link Speed = 6.0Gb/s
## NCQ setting = N/A
## Write Cache = Enabled
## Logical Sector Size = 512B
## Physical Sector Size = 4 KB
## Connector Name = 00
## 
	    $inHD = 0;
	    $complete = 0;
	    $slot = "";
	    $modell = "";
	    $serial = "";

	    while (<PROGOUT>) {
		chomp;
		next if ( $inHD == 0 and $_ !~ /^Drive.*Device attributes :/ );
		print "drive details: $_\n" if $main::debug;
		if ( /^Drive \/c$controllerId\/e$enclosureId\/s(\d+)\s+Device attributes :/i ) {
		    $slot = $1;
		    print "C: $controllerId E: $enclosureId S: $slot\n" if $main::debug;
		    $inHD = 1;
		}
		elsif ( /^SN =\s+(\w+.*)\s*$/ ) {
		    $serial = $1;
		    print "Serial: $serial\n" if $main::debug;
		}
		elsif ( /^Model Number =\s+(\S+.*)\s*$/ ) {
		    $modell = $1;
		    print "Modell: $modell\n" if $main::debug;
		}
		elsif ( $complete == 0 and length $enclosureId and length $slot and length $modell and length $serial  ) {
		    # we have all infos for a disk we look for
		    $complete = 1;
	# match against diskidentifier hash, set Slot attribute per disk
		    print "controller: $controllerId, encl: $enclosureId, slot: $slot, modell: $modell, serial: $serial\n" if $main::debug;
		    $modell =~ s/\s*$//;
		    $modell =~ s/^\S+\s+//i if $modell =~ /\s/;     # drop Manufacturer as in "WDC WD2000F9YZ-0" or "Hitachi HUA72302"
		    $serial =~ s/\s*$//;
		    foreach $currentdiskid ( keys %diskidenthash ) {
			if ( $currentdiskid =~ /$modell.*\.$serial/i ) {
			    print "found $diskidenthash{$currentdiskid} at T:C:E:S: $controllertype:$controllerId:$enclosureId:$slot\n" if $main::debug;
			    foreach my $curdisk ( split ( /, /, $diskidenthash{$currentdiskid} ) ) {
				# consider multipathing
				$smart->{$curdisk}{slotinfo} .= $smart->{$curdisk}{slotinfo} ? ", $controllertype:$controllerId:$enclosureId:$slot" : "$controllertype:$controllerId:$enclosureId:$slot";
			    }
			} else {
			    my $tempmodell;
			    my $tempserial;
			    ($tempmodell, $tempserial) = split (/\./, $currentdiskid);
			    if ( "$modell\.$serial" =~ /$tempmodell.*\.$tempserial/i ) {
				print "altfound $diskidenthash{$currentdiskid} at T:C:E:S: $controllertype:$controllerId:$enclosureId:$slot\n" if $main::debug;
				foreach my $curdisk ( split ( /, /, $diskidenthash{$currentdiskid} ) ) {
				    # consider multipathing
				    $smart->{$curdisk}{slotinfo} .= $smart->{$curdisk}{slotinfo} ? ", $controllertype:$controllerId:$enclosureId:$slot" : "$controllertype:$controllerId:$enclosureId:$slot";
				}
			    }
			}
		    }
		    $inHD = 0;
		    $serial = "";
		    $modell = "";
		    $slot = "";
		    $complete = 0;
		} elsif ( /^Drive.*Policies\/Settings :/ ) {
		    $inHD = 0;
                    $serial = "";
                    $modell = "";
                    $slot = "";
                    $complete = 0;
		}
	    }
	    close (PROGOUT);
	}
    }
}

1;
