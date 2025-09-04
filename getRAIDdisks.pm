package lsdiskowipe::getRAIDdisks;
use strict;
use warnings;
use Data::Dumper;

sub sortDiskNames {
    my $deltal = length( $a ) - length( $b );
    return ($deltal ? $deltal : $a cmp $b);
}

# 
# if we want to get informations from the individual physical disks that are included in a RAID array
# we should provide the parameters smartctl will need to grab the infos from the disk
#
sub getRAIDdisks {
    my $p_hdd = $_[0];	# disklistpointer
    my $p_ctrl = $_[1];	# controllerlistpointer

    #print Dumper ( %$p_hdd );
    #
    # here goes the detection of physical disks of a hardware RAID per virtual disk shown to os
    # so split logical disk in its physical components
    my %PDfromRAID = (
    	"megaraid_sas"	=> { "prgm"	=> "VD2PD_megaraid_sas" },
    	"3w-9xxx"	=> { "prgm"     => "VD2PD_3w9xxx" },
    	"aacraid"	=> { "prgm"     => "VD2PD_aacraid"},
    );
    # to need just one call for RAID details per controller we accumulate the infos
    foreach my $hddId ( sort sortDiskNames keys %$p_hdd ) {
    	my $host    = $$p_hdd{$hddId}{host};	# host is the controller type
    	my $driver  = $p_ctrl->{$host}{driver} ? $p_ctrl->{$host}{driver} : 'unknown' ;
	my $channel = $$p_hdd{$hddId}{channel};	# channel is id of the controller (needed if mote than one per type exists)
    
    	if ( defined $PDfromRAID{$driver} ) {
	    push @{$PDfromRAID{$driver}{channels}{$channel}{disks}}, $hddId;
    	}
    }

    #print Dumper ( %PDfromRAID );
    my $ctrlidx = 0;
    foreach my $ctrlType ( keys %PDfromRAID ) {
	if ( defined $PDfromRAID{$ctrlType}{channels} ) {
	    foreach my $channel ( keys %{$PDfromRAID{$ctrlType}{channels}} ) {
		my $VD2PD = "$PDfromRAID{$ctrlType}{prgm} ( \$p_hdd, \$ctrlidx, \$channel, \\\@{\$PDfromRAID{$ctrlType}{channels}{$channel}{disks}});";
		print "eval $VD2PD\n" if $main::debug;
		eval $VD2PD;
		$ctrlidx++;
	    }
	}
    }
    
}

sub VD2PD_megaraid_sas {
    my $p_hdd = $_[0];
    my $ctrlidx = $_[1];
    my $channel = $_[2];
    my $p_disks = $_[3];

#    print Dumper ( %$p_hdd );
#    print Dumper ( $channel );
#    print Dumper ( @$p_disks );

    my $infprog = "storcli";

    if ( not `sh -c "which $infprog"` ) {
        print "ERROR: required program \"$infprog\" not found, -> install it to continue. Aborting!\n";
        exit 2;
    }

    print "$infprog: reading controller $ctrlidx\n" if $main::verbose;
    # get disk distribution info
    open (PROGOUT, "$infprog /c$ctrlidx show |") || die "getting infos from $infprog controller #$ctrlidx failed";
# sample output
## # storcli /c0 show
## ...
## TOPOLOGY :
## ========
## 
## ---------------------------------------------------------------------------
## DG Arr Row EID:Slot DID Type  State BT     Size PDC  PI SED DS3  FSpace TR
## ---------------------------------------------------------------------------
##  0 -   -   -        -   RAID0 Optl  N  931.0 GB dflt N  N   dflt N      N
##  0 0   -   -        -   RAID0 Optl  N  931.0 GB dflt N  N   dflt N      N
##  0 0   0   32:0     0   DRIVE Onln  N  931.0 GB dflt N  N   dflt -      N
##  1 -   -   -        -   RAID0 Optl  N  931.0 GB dflt N  N   dflt N      N
##  1 0   -   -        -   RAID0 Optl  N  931.0 GB dflt N  N   dflt N      N
##  1 0   0   32:1     1   DRIVE Onln  N  931.0 GB dflt N  N   dflt -      N
## ---------------------------------------------------------------------------
## 
## DG=Disk Group Index|Arr=Array Index|Row=Row Index|EID=Enclosure Device ID
## DID=Device ID|Type=Drive Type|Onln=Online|Rbld=Rebuild|Dgrd=Degraded
## Pdgd=Partially degraded|Offln=Offline|BT=Background Task Active
## PDC=PD Cache|PI=Protection Info|SED=Self Encrypting Drive|Frgn=Foreign
## DS3=Dimmer Switch 3|dflt=Default|Msng=Missing|FSpace=Free Space Present
## TR=Transport Ready
## 
## Virtual Drives = 2
## 
## VD LIST :
## =======
## 
## --------------------------------------------------------------------
## DG/VD TYPE  State Access Consist Cache Cac sCC     Size Name
## --------------------------------------------------------------------
## 0/2   RAID0 Optl  RW     Yes     RWBD  -   OFF 931.0 GB SSD Group 0
## 1/3   RAID0 Optl  RW     Yes     RWBD  -   OFF 931.0 GB SSD Group 1
## --------------------------------------------------------------------
## 
## Cac=CacheCade|Rec=Recovery|OfLn=OffLine|Pdgd=Partially Degraded|Dgrd=Degraded
## Optl=Optimal|RO=Read Only|RW=Read Write|HD=Hidden|TRANS=TransportReady|B=Blocked|
## Consist=Consistent|R=Read Ahead Always|NR=No Read Ahead|WB=WriteBack|
## FWB=Force WriteBack|WT=WriteThrough|C=Cached IO|D=Direct IO|sCC=Scheduled
## Check Consistency
## 
## Physical Drives = 2
## 
## PD LIST :
## =======
## 
## ------------------------------------------------------------------------------
## EID:Slt DID State DG     Size Intf Med SED PI SeSz Model                   Sp
## ------------------------------------------------------------------------------
## 32:0      0 Onln   0 931.0 GB SATA SSD Y   N  512B Samsung SSD 860 EVO 1TB U
## 32:1      1 Onln   1 931.0 GB SATA SSD Y   N  512B Samsung SSD 860 EVO 1TB U
## ------------------------------------------------------------------------------
## 
## EID-Enclosure Device ID|Slt-Slot No.|DID-Device ID|DG-DriveGroup
## DHS-Dedicated Hot Spare|UGood-Unconfigured Good|GHS-Global Hotspare
## UBad-Unconfigured Bad|Onln-Online|Offln-Offline|Intf-Interface
## Med-Media Type|SED-Self Encryptive Drive|PI-Protection Info
## SeSz-Sector Size|Sp-Spun|U-Up|D-Down/PowerSave|T-Transition|F-Foreign
## UGUnsp-Unsupported|UGShld-UnConfigured shielded|HSPShld-Hotspare shielded
## CFShld-Configured shielded|Cpybck-CopyBack|CBShld-Copyback Shielded
## 
## ...

## or (in case of JBOD disks configured)
## ...
## JBOD LIST :
## =========
## 
## -------------------------------------------------------------------------------
## EID:Slt DID State DG     Size Intf Med SED PI SeSz Model               Sp Type
## -------------------------------------------------------------------------------
## 32:0      0 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:1      1 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:2      2 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:3      3 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## -------------------------------------------------------------------------------
## 
## ID=JBOD Target ID|EID=Enclosure Device ID|Slt=Slot No|DID=Device ID|Onln=Online
## Offln=Offline|Intf=Interface|Med=Media Type|SeSz=Sector Size
## SED=Self Encryptive Drive|PI=Protection Info|Sp=Spun|U=Up|D=Down
## 
## Physical Drives = 4
## 
## PD LIST :
## =======
## 
## -------------------------------------------------------------------------------
## EID:Slt DID State DG     Size Intf Med SED PI SeSz Model               Sp Type
## -------------------------------------------------------------------------------
## 32:0      0 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:1      1 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:2      2 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## 32:3      3 JBOD  -  1.746 TB SATA SSD N   N  512B INTEL SSDSC2KB019TZ U  -
## -------------------------------------------------------------------------------
## ...
## 
## in this JBOD case the caption is the same for JBOD LIST and PD LIST (both look
## the same way as PD LIST for RAID) but without preceding TOPOLOGY section
## that is: we simply see no DG (drive group)

    my @TOPology;
    my $TOPfound = 0; # 0: not yet, 1: Caption found, 2: first separator, 3: 2nd separator, we're off 
    my @VDlist;
    my $VDfound = 0;  # like TOPfound
    my @JBODlist;
    my $JBODfound = 0; #same procedure

    while (<PROGOUT>) {
	# print;
	chomp;
	# first we expect TOPOLOGY INFO
	# we need TOPOLOGY INFO later, so we save it 
	if ( $TOPfound == 0 and $_ =~ /^DG\s+Arr\s+Row\s+EID:Slot\s+DID/ ) {
	    $TOPfound = 1;
	    push @TOPology, $_;
	} elsif ( $TOPfound == 1 ) {
	    if ( $_ =~ /^---------------------------/ ) {
		$TOPfound = 2;
	    } else {
		print "unexpected situation 1 in $infprog parsing, have $_\n";
	    }
	} elsif ( $TOPfound == 2 ) {
	    if ( $_ =~ /^---------------------------/ ) {
		$TOPfound = 3;
	    } else {
		push @TOPology, $_;
	    }
	} elsif ( $TOPfound == 3 and $VDfound == 0 and $_ =~ /^DG\/VD\s+TYPE\s+State/ ) {
	    $VDfound = 1;
	    push @VDlist, $_;
	} elsif ( $VDfound == 1 ) {
	    if ( $_ =~ /^---------------------------/ ) {
		$VDfound = 2;
	    } else {
		print "unexpected situation 2 in $infprog parsing, have $_\n";
	    }
	} elsif ( $VDfound == 2 ) {
	    if ( $_ =~ /^---------------------------/ ) {
		$VDfound = 3;
	    } else {
		push @VDlist, $_;
	    }
	} elsif ( $VDfound == 3 ) {
	    # we're done
	    last;
	} elsif ( $JBODfound == 0 and $_ =~ /^EID:Slt\s+DID\s+State\s+DG\s+/ ) {
	    $JBODfound = 1;
	    push @JBODlist, $_;
	} elsif ( $JBODfound == 1 ) {
	    if ( $_ =~ /^---------------------------/ ) {
		$JBODfound = 2;
	    } else {
	        print "unexpected situation 3 in $infprog parsing, have $_\n";
	    }
	} elsif ( $JBODfound == 2 ) {
	    if ( $_ =~ /^---------------------------/ ) {
	        $JBODfound = 3;
	    } else {
	        push @JBODlist, $_;
	    }
	} elsif ( $JBODfound == 3 ) {
	    # that's it
	    last;
	}

    }
    close (PROGOUT);

    print "TOPOLOGY found: $TOPfound\nVirtualDisks found: $VDfound\nJBOD found: $JBODfound\n" if $main::debug;

    foreach my $hddId (@$p_disks) {
	my $pDiskIdx = 0;
	my %curHdd = %$p_hdd{$hddId};
	my $DG;
	my $VD;
	my $DID;
	my $curVD = $$p_hdd{$hddId}{id};
	if ( $VDfound == 3 ) {
	    # find matching VD to get DG from VDLIST
	    foreach my $VDline ( @VDlist ) {
		if ( $VDline =~ /^(\d+)\/(\d+)\s+/ ) {
		    $DG = $1;
		    $VD = $2;
		    if ( $curVD == $VD ) {
			print "disk $hddId DG: $DG VD: $VD\n" if $main::debug;
			# we assume we find only one DG per logical disk
			last;
		    }
		}
	    }
	    # and now get the DID (drive IDs) for the physical disks
	    foreach my $TOPline ( @TOPology ) {
		if ( $TOPline =~ /^\s+$DG\s+\d+\s+\d+\s+[\d:]+\s+(\d+)\s+DRIVE\s+/ ) {
		    $DID = $1;
    #	    	print "matching TOPline $TOPline\n";
    #		print Dumper ($curHdd{$hddId});
		    $p_hdd->{"$hddId.$pDiskIdx"} = $curHdd{$hddId};
		    $p_hdd->{"$hddId.$pDiskIdx"}{DID} = $DID;
		    delete $p_hdd->{$hddId} if ($pDiskIdx == 0);
		    $pDiskIdx++;
		}
	    }
	} elsif ( $JBODfound == 3 ) {
	    # handle JBOD disks
	    foreach my $JBODline ( @JBODlist ) {
	        if ( $JBODline =~ /^\d+:\d+\s+$curVD\s+JBOD\s+\-\s+/ ) {
		    $DID = $curVD;
		    # the id from the lsscsi -g is our DID apparently
		    # let's label this disk
		    $p_hdd->{$hddId}{JBOD} = 1;
		    $p_hdd->{$hddId}{DID} = $DID;
		}
	    }
	}

    }

#    print Dumper (%$p_hdd);
    
###    }
}

sub VD2PD_3w9xxx {
    my $p_hdd = $_[0];
    my $channel = $_[1];
    my $p_disks = $_[2];

#    print Dumper ( %$p_hdd );
#    print Dumper ( $channel );
#    print Dumper ( @$p_disks );

    print "RAID disk handling on 3w-9xxx not yet implemented, aborting\n";
    exit 22;
}

sub VD2PD_aacraid {
    my $p_hdd = $_[0];
    my $channel = $_[1];
    my $p_disks = $_[2];

#    print Dumper ( %$p_hdd );
#    print Dumper ( $channel );
#    print Dumper ( @$p_disks );

    print "RAID disk handling on aacraid not yet implemented, aborting\n";
    exit 23;
}

1;
