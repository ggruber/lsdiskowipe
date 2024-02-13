package getSlotInfo;
use strict;
use warnings;
use readSmartData;
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
	"nvme"         => "sltinf_none",
	"uas"          => "sltinf_none",
	"usb-storage"  => "sltinf_none",
	"3w-9xxx"      => "unimplemented", # twcli
	"3w-sas"       => "unimplemented", # twcli
	"mptsas"       => "unimplemented", # lsimega
	"mpt2sas"      => "sltinf_sas23ircu",
	"mpt3sas"      => "sltinf_sas23ircu",
	"megaraid_sas" => "unimplemented", # storcli
	"aacraid"      => "unimplemented", # arcconf
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
    my @controlleridxs;
    my $controller;

    if ( not `sh -c "which $infprog"` ) {
	die "required program \"$infprog\" not found, install it to continue\n";
    }
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
    print "$infprog Controllers found ( " . scalar @controlleridxs ." ), index: @controlleridxs\n"  if $main::debug;
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
			    $smart->{$curdisk}{slotinfo} = "$controllertype:$controller:$enclosure:$slot";
			}
		    } else {
			my $tempmodell;
			my $tempserial;
			($tempmodell, $tempserial) = split (/\./, $currentdiskid);
			if ( "$modell\.$serial" =~ /$tempmodell.*\.$tempserial/i ) {
			    print "altfound $diskidenthash{$currentdiskid} at T:C:E:S: $controllertype:$controller:$enclosure:$slot\n" if $main::debug;
			    foreach my $curdisk ( split ( /, /, $diskidenthash{$currentdiskid} ) ) {
				$smart->{$curdisk}{slotinfo} = "$controllertype:$controller:$enclosure:$slot";
			    }
			}
		    }
		}
	    }
	        
	}
	close (PROGOUT);
    }
}

1;
