#
# get basic (and some extended) information from every single disk
#

package lsdiskowipe::readSmartData;
use strict;
use warnings;
use lsdiskowipe::getRAIDdisks;
use Data::Dumper;

sub sortDiskNames {
    my $deltal = length( $a ) - length( $b );
    return ($deltal ? $deltal : $a cmp $b);
}

sub readSmartData {
    my $smart          = $_[0];	# ptr to smart data structure
    my $uc_blacklist   = $_[1]; # ptr to unconditional blacklist
    #
    # detection if output is useful should be added to the lsscsi calls
    # in the sense of robustness of the programm
    #
    my %ctrl;
    my %hdd;
    my $twa = 0;
    my $has_nvme = 0;
    my @nvmedisks;

    my @controllerData = `lsscsi -H`;	# list the SCSI hosts and NVMe controllers currently attached to the system
    					# looks like:
					# [0]    ahci
					# [1]    ahci
					# [2]    mpt2sas
					#
    foreach my $line (@controllerData) {
        chomp $line;
        if ( $line =~ /\[(\d+)\]\s+(\S+)\s*/ ) {
            my $id     = $1;
            my $driver = $2;
            $ctrl{$id}{driver} = $driver;
            if ( $driver =~ /^3w-9xxx$/ ) {
                $ctrl{$id}{twa}     = $twa;
		# find the required helper program
		my $twcli_program = "";
                if ( not `sh -c "which tw_cli"` ) {
		    if ( not `sh -c "which tw-cli"` ) {
			die "required program \"tw_cli\" or \"tw-cli\" not found, go and get it";
		    } else {
			$twcli_program = "tw-cli";
		    }
		} else {
		    $twcli_program = "tw_cli";
		}

                my @twData =  `$twcli_program \/c$id show`;
                $ctrl{$id}{twData}  = \@twData;
                $twa++;
            }
        } elsif ( $line =~ /^\[(N:\d+)\]/ ) {
            if ( not $has_nvme ) {
                $has_nvme = 1;
                if ( not `sh -c "which nvme"` ) {
		    die "required program \"nvme\" not found, re-run installer";
		}
            }
	    my $id     = $1;
	    my $driver = "nvme";
            $ctrl{$id}{driver} = $driver;
	} else {
	    print "unknown line for controllerdata: $line\n" if ( $main::verbose or $main::debug );
	}

    }

    my @hddData        = `lsscsi -g`;	# list virtual disks on RAID Controllers if not in HBA/JBOD mode
    					# looks like:
					# [2:0:0:0]    disk    ATA      ST4000NM000B-2TF TN01  /dev/sda   /dev/sg0
    foreach my $line (@hddData) {
	print $line if ( $main::debug );
        chomp $line;
	# [0:0:0:0]    disk    ATA      WDC WD2000F9YZ-0 1A02  /dev/sda   /dev/sg0
	# [0:2:3:0]    disk    DELL     PERC H710        3.13  /dev/sda   /dev/sg1
	# [N:0:0:1]    disk    INTEL SSDPEK1W060GA__1                     /dev/nvme0n1  -
        if ($line =~ /^\[(\d+):(\d+):(\d+):(\d+)\]\s+disk\s+(.*\S)\s+\/dev\/(sd\w+)\s+\/dev\/(\w+)\n?/) {
	    next if ( grep ( /^\/dev\/$5$/, @$uc_blacklist ) );  # omit uc blacklisted disks
            $hdd{$6}{host}    = $1;
            $hdd{$6}{channel} = $2;
            $hdd{$6}{id}      = $3;
            $hdd{$6}{lun}     = $4;
            $hdd{$6}{descrip} = $5;
            $hdd{$6}{sata}    = $6;
            $hdd{$6}{scsi}    = $7;
        } elsif ($line =~ /^\[(N:\d+):(\d+):(\d+)\]\s+disk\s+(.*\S)\s+\/dev\/(nvme\w+)n1\s+\-\n?/) {
	    next if ( grep ( /^\/dev\/$4$/, @$uc_blacklist ) );  # omit uc blacklisted disks
	    $hdd{$5}{host}    = $1;
            $hdd{$5}{id}      = $2;
            $hdd{$5}{lun}     = $3;
            $hdd{$5}{descrip} = $4;
	    $hdd{$5}{sata}    = $5;
	    $hdd{$5}{scsi}    = "";
	    push ( @nvmedisks, "$5" );
	} elsif ($line =~ /^\[[N\d]+:\d+:\d+:\d+\]\s+(\S+)\s+/) {
	    if ("$1" eq "disk") {
	        print "unknown line for diskdata: $line\n";
	    } else {
		print "ignoring non-disk: $line\n" if ( $main::debug );
	    }
	}
    }
    #
    # kind of doubled main loop
    # gather "basic" information from all disks
    #
    # first: are there Virtual Disks (VD) from RAID Controller?
    #        -> get the physical disks
    #
    lsdiskowipe::getRAIDdisks::getRAIDdisks ( \%hdd, \%ctrl );

    # we possibly now have RAID disks injected with disknames with appendices like sda.0, sda.1 ...
    # (keys in hash should be unique, shouldn't they?)

    #
    # second: get the details from the physical disks
    #
    foreach my $hddId ( sort sortDiskNames keys %hdd ) {
	my $lhddId;	# logical hhdId
	my $phddId;	# physical hhdId
        my @smartData;
	my @T10PI_Data;
	my @CRYPT_Data;
	my @HPA_Data;
	my @DCO_Data;
	my $inSecurity = 0;
	my $securitySupported = 0;
	my $SASignoreNextIFSpeed = 0;
        my $host       = $hdd{$hddId}{host};
	print "hddId\{host\}: $hddId\{$host\} " if $main::debug;
        $hdd{$hddId}{blanked}   = 0;
        $hdd{$hddId}{erased}    = 0;
	# info on driver if verbose is requested
	my $driver =  $ctrl{$host}{driver} ? $ctrl{$host}{driver} : 'unknown' ;
	print "hddId:driver $hddId:$driver\n" if $main::debug;
	$smart->{$hddId}{driver} = $driver;

	# should be reviewed and better handled as regular RAID disks
	# code will possibly work never more
        if ( $ctrl{$host}{driver} eq "3w-9xxx" ) {
            foreach my $twHdd (@{ $ctrl{$host}{twData} }) {
                if ( $twHdd =~ /^p(\d+)\s+\w+\s+u$hdd{$hddId}{id}.*$/i ) {
                    $hdd{$hddId}{twId} = $1;
                }
            }
        } elsif ( $ctrl{$host}{driver} eq "nvme" ) {
	    $smart->{$hddId}{transport} = "nvme";
	    $smart->{$hddId}{rotation} = "SSD";
	}

	# some handling for RAID physical disks
	if ( $hddId !~ /\./ ) {
	    $lhddId = $hddId;
	    if ( defined $hdd{$hddId}{JBOD} and $hdd{$hddId}{JBOD} == 1 ) {
		if ( defined $hdd{$hddId}{DID} ) {
		    $phddId = $hdd{$hddId}{DID};
		} else {
		    print "Error: missing physical driveID for JBOD disk $hddId, so skipping it\n";
		    next;
		}
	    }
	} else {
	    $lhddId = $hdd{$hddId}{sata} ? $hdd{$hddId}{sata} : $hddId;
	    if ( defined $hdd{$hddId}{DID} ) {
		$phddId = $hdd{$hddId}{DID};
	    } else {
		print "Error: missing physical driveID for disk $hddId, so skipping it\n";
		next;
	    }
	}

        my %ctrlChoice = (
            "ahci"          => sub { @smartData = `smartctl -a /dev/$lhddId` },
            "uas"           => sub { @smartData = `smartctl -a /dev/$lhddId` },
            "pata_jmicron"  => sub { @smartData = `smartctl -a /dev/$lhddId` },
            "nvme"          => sub { @smartData = `smartctl -a /dev/$lhddId` },
	    "usb-storage"   => sub { @smartData = `smartctl -a /dev/$hdd{$hddId}{scsi}` },
            # not seen SAS disks on ahci, uas or nvme so -a seems sufficient
            # else -x to get interface speed for SAS drives
            "3w-9xxx"       => sub { @smartData = `smartctl -x -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa}` },
            "3w-sas"        => sub { @smartData = `smartctl -x -d 3ware,$hdd{$hddId}{id} /dev/$hddId` },
            "mptsas"        => sub { @smartData = `smartctl -x /dev/$hdd{$hddId}{scsi}` },
            "mpt2sas"       => sub { @smartData = `smartctl -x /dev/$hdd{$hddId}{scsi}` },
            "mpt3sas"       => sub { @smartData = `smartctl -x /dev/$hdd{$hddId}{scsi}` },
            "megaraid_sas"  => sub { @smartData = `smartctl -x -d megaraid,$phddId /dev/$lhddId` },
            "aacraid"       => sub { @smartData = `smartctl -x $hdd{$hddId}{scsi}` }
            # aacraid SAS does only work without -d sat. A solution for SATA and SAS still needs to be implemented.
        );

	# problems with disks from RAID drives here
	my %ctrlChoice2a = (
            "ahci"          => sub { @T10PI_Data = `sg_readcap -l /dev/$lhddId 2>/dev/null` },
            "nvme"          => sub { @T10PI_Data = `sg_readcap -l /dev/$lhddId 2>/dev/null` },
            "uas"           => sub { @T10PI_Data = `sg_readcap -l /dev/$lhddId 2>/dev/null` },
            "pata_jmicron"  => sub { @T10PI_Data = `sg_readcap -l /dev/$lhddId 2>/dev/null` },
	    "usb-storage"   => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$lhddId}{scsi} 2>/dev/null` },
            "3w-9xxx"       => sub { @T10PI_Data = `sg_readcap -l -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa} 2>/dev/null` },
            "3w-sas"        => sub { @T10PI_Data = `sg_readcap -l -d 3ware,$hdd{$hddId}{id} /dev/$hddId 2>/dev/null` },
            "mptsas"        => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$lhddId}{scsi} 2>/dev/null` },
            "mpt2sas"       => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$lhddId}{scsi} 2>/dev/null` },
            "mpt3sas"       => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$lhddId}{scsi} 2>/dev/null` },
            "megaraid_sas"  => sub { @T10PI_Data = `sg_readcap -l /dev/$hddId 2>/dev/null` },
            "aacraid"       => sub { @T10PI_Data = `sg_readcap -l $hdd{$hddId}{scsi} 2>/dev/null` }
        );

	my %ctrlChoice2b = (
            "ahci"          => sub { @CRYPT_Data = `hdparm -I /dev/$hddId 2>/dev/null` },
            "nvme"          => sub { @CRYPT_Data = `hdparm -I /dev/$hddId 2>/dev/null` },
            "uas"           => sub { @CRYPT_Data = `hdparm -I /dev/$hddId 2>/dev/null` },
            "pata_jmicron"  => sub { @CRYPT_Data = `hdparm -I /dev/$hddId 2>/dev/null` },
            "usb-storage"   => sub { @CRYPT_Data = `hdparm -I /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "3w-9xxx"       => sub { @CRYPT_Data = `hdparm -I -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa} 2>/dev/null` },
            "3w-sas"        => sub { @CRYPT_Data = `hdparm -I -d 3ware,$hdd{$hddId}{id} /dev/$hddId 2>/dev/null` },
            "mptsas"        => sub { @CRYPT_Data = `hdparm -I /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt2sas"       => sub { @CRYPT_Data = `hdparm -I /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt3sas"       => sub { @CRYPT_Data = `hdparm -I /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "megaraid_sas"  => sub { @CRYPT_Data = `hdparm -I /dev/$hddId 2>/dev/null` },
            "aacraid"       => sub { @CRYPT_Data = `hdparm -I $hdd{$hddId}{scsi} 2>/dev/null` }
        );

	# problems with disks from RAID drives here
	my %ctrlChoice3 = (
            "ahci"          => sub { @HPA_Data = `hdparm -N /dev/$hddId 2>/dev/null` },
            "nvme"          => sub { @HPA_Data = `hdparm -N /dev/$hddId 2>/dev/null` },
            "uas"           => sub { @HPA_Data = `hdparm -N /dev/$hddId 2>/dev/null` },
            "pata_jmicron"  => sub { @HPA_Data = `hdparm -N /dev/$hddId 2>/dev/null` },
	    "usb-storage"   => sub { @HPA_Data = `hdparm -N /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "3w-9xxx"       => sub { @HPA_Data = `hdparm -N -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa} 2>/dev/null` },
            "3w-sas"        => sub { @HPA_Data = `hdparm -N -d 3ware,$hdd{$hddId}{id} /dev/$hddId 2>/dev/null` },
            "mptsas"        => sub { @HPA_Data = `hdparm -N /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt2sas"       => sub { @HPA_Data = `hdparm -N /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt3sas"       => sub { @HPA_Data = `hdparm -N /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "megaraid_sas"  => sub { @HPA_Data = `hdparm -N /dev/$hddId 2>/dev/null` },
            "aacraid"       => sub { @HPA_Data = `hdparm -N $hdd{$hddId}{scsi} 2>/dev/null` }
        );

	# problems with disks from RAID drives here
	my %ctrlChoice4 = (
            "ahci"          => sub { @DCO_Data = `hdparm --dco-identify /dev/$hddId 2>/dev/null` },
            "nvme"          => sub { @DCO_Data = `hdparm --dco-identify /dev/$hddId 2>/dev/null` },
            "uas"           => sub { @DCO_Data = `hdparm --dco-identify /dev/$hddId 2>/dev/null` },
            "pata_jmicron"  => sub { @DCO_Data = `hdparm --dco-identify /dev/$hddId 2>/dev/null` },
	    "usb-storage"   => sub { @DCO_Data = `hdparm --dco-identify /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "3w-9xxx"       => sub { @DCO_Data = `hdparm --dco-identify -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa} 2>/dev/null` },
            "3w-sas"        => sub { @DCO_Data = `hdparm --dco-identify -d 3ware,$hdd{$hddId}{id} /dev/$hddId 2>/dev/null` },
            "mptsas"        => sub { @DCO_Data = `hdparm --dco-identify /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt2sas"       => sub { @DCO_Data = `hdparm --dco-identify /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "mpt3sas"       => sub { @DCO_Data = `hdparm --dco-identify /dev/$hdd{$hddId}{scsi} 2>/dev/null` },
            "megaraid_sas"  => sub { @DCO_Data = `hdparm --dco-identify /dev/$hddId 2>/dev/null` },
            "aacraid"       => sub { @DCO_Data = `hdparm --dco-identify $hdd{$hddId}{scsi} 2>/dev/null` }
        );

	#
	# get majority of SMART information
	#
        if ( defined $ctrlChoice{ $ctrl{$host}{driver} } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice{ $ctrl{$host}{driver} }->();	# here work gets done
	    # if there are some slow SAS disks show activity
            print ".";
	    # quirk #2
	    if ( $ctrl{$host}{driver} eq "megaraid_sas" ) {
		# magic controller change here?
	    }
        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver}, please file a feature request for it.\n";
	    next;
	}

	$smart->{$hddId}{lhddId} = $lhddId;
	$smart->{$hddId}{phddId} = $phddId;
	$smart->{$hddId}{shddId} = $hdd{$hddId}{scsi};
	$smart->{$hddId}{cntrlr} = $ctrl{$host}{driver};

        foreach my $line (@smartData) {
	    print $line if $main::Debug;
            chomp $line;
            if ( $line =~ /Model\sFamily:\s+(.+)$/ or $line =~ /^Vendor:\s+(.+)$/i ) {
                $smart->{$hddId}{vendor} = $1;
            }
            if ( $line =~ /Model\sFamily:\s+Seagate\s+.*([457][0-9][0-9]0)[^0-9]/ ) {
                $smart->{$hddId}{rotation} = $1;
            }
	    # use only if first method gave no result (so far)
            if (  !(defined $smart->{$hddId}{vendor} and $smart->{$hddId}{vendor} ne "" ) and $line =~ /Add\.\sProduct\sId:\s+(.+)$/i ) {
                $smart->{$hddId}{vendor} = $1;
            }
	    elsif ( $line =~ /A mandatory SMART command failed/i ) {
		$smart->{$hddId}{health} = "SMART_READ_PROBLEM";
	    }
            elsif ( $line =~ /Device\sModel:\s+(.+)$/ or $line =~ /^Product:\s+(.+)$/i or $line =~ /^Model Number:\s+(.+)$/i ) {
                $smart->{$hddId}{devModel} = $1;
            }
            elsif ( $line =~ /Serial\sNumber:\s+(.+)$/i ) {
                $smart->{$hddId}{serial} = $1;
            }
            elsif ( $line =~ /Firmware\sVersion:\s+(.+)$/i ) {
                $smart->{$hddId}{firmware} = $1;
            }
            elsif ( $line =~ /Revision:\s+(.+)$/i ) {
                $smart->{$hddId}{firmware} = $1;
            }
            elsif ( $line =~ /User\sCapacity:\s+.+\[(.+)\]$/i  or $line =~ /Total\sNVM\sCapacity:\s+.+\[(.+)\]$/i) {
                $smart->{$hddId}{capacity} = $1;
            }
	    elsif ( not $smart->{$hddId}{capacity} and $line =~ /Namespace\s1\sSize\/Capacity:\s+.+\[(.+)\]$/i) {
                $smart->{$hddId}{capacity} = $1;
            }
            elsif ( $line =~ /Rotation Rate:\s+(.+)$/i ) {
                if ( $1 =~ /Solid State/i ) {
                    $smart->{$hddId}{rotation} = "SSD";
                } elsif ($1 =~ /^(\d+)/){
		    $smart->{$hddId}{rotation} = $1;
                } else {
                    $smart->{$hddId}{rotation} = "UNKN";
                }
            }
            elsif ( $line =~ /sector size/i or $line =~ /logical block size/i or $line =~ /formatted lba size/i ) {
                # just check for two or one numbers on the line
                if ( $line =~ /^.*:\s+(\d+)\s+[^0-9]+\s+(\d+)\s*[^0-9]*$/ ) {
                    $smart->{$hddId}{sectSize} = "$1/$2";
                } elsif ( $line =~ /^.*:\s+(\d+)\s*[^0-9]*$/ ) {
                    $smart->{$hddId}{sectSize} = "$1";
                }
            }
            elsif ( $line =~ /physical block size/i ) {
                # we assume only one number on this line
                if ( $line =~ /^.*:\s+(\d+)\s*[^0-9]*$/ ) {
		    $smart->{$hddId}{sectSize} = $smart->{$hddId}{sectSize} ? "$smart->{$hddId}{sectSize}/$1" : $1;
                } else {
		    print "expected byte count for logical block size not found\n" if ( $main::verbose or $main::debug );
		    print "$line\n" if ( $main::verbose or $main::debug );
                }
            }
            elsif ( $line =~ /SATA\sVersion\sis:\s+SATA.*$/i ) {
		if ( defined $ctrl{$host}{driver} and $ctrl{$host}{driver} eq "uas" ) {
		    $smart->{$hddId}{transport} = "uas-sata";
		} else {
		    $smart->{$hddId}{transport} = "sata";
		}
            }
	    elsif ( $line =~ /ATA\sVersion\sis:\s+ATA.*$/i ) {
		if ( defined $ctrl{$host}{driver} and $ctrl{$host}{driver} eq "usb-storage" ) {
		    $smart->{$hddId}{transport} = "uas-ata";
		} else {
                    $smart->{$hddId}{transport} = "ata";
                }
	    }
            elsif ( $line =~ /Transport protocol:\s+SAS.*$/ ) {
                $smart->{$hddId}{transport} = "sas";
		if ( $line =~ /Transport protocol:\s+SAS\s+\((SPL-[1-5])\)/i ) {
		    my $SASstd = $1;
		    print "SASstd $SASstd\n" if $main::debug;
		    if ( $SASstd eq "SPL-1" ) {
		        $smart->{$hddId}{ifSpeed} = "3 Gbit/s";
		    } elsif ( $SASstd eq "SPL-2" ) {
		        $smart->{$hddId}{ifSpeed} = "6 Gbit/s";
		    } elsif ( $SASstd eq "SPL-3" ) {
		        $smart->{$hddId}{ifSpeed} = "12Gbit/s";
		    } elsif ( $SASstd eq "SPL-4" ) {
		        $smart->{$hddId}{ifSpeed} = "22.5Gbit/s";
		    } elsif ( $SASstd eq "SPL-5" ) {
		        $smart->{$hddId}{ifSpeed} = "45Gbit/s";
		    }
		}
            }
            elsif ( $line =~ /SMART\soverall-health.+:\s+(\w+)$/i ) {
                $smart->{$hddId}{health} = $1;
            }
            elsif ( $line =~ /SMART\sHealth\sStatus:\s+(.+)$/i ) {
                if($1 =~ /error/i) {
                    $smart->{$hddId}{health} = "ERROR";
                }
                elsif($1 =~ /failure/i) {
                    $smart->{$hddId}{health} = "FAILURE";
                }
                elsif($1 =~ /ok/i) {
                    $smart->{$hddId}{health} = "OK";
                }
            }
	    elsif ( $line =~ /Percent_Life_Remaining\s+|SSD_Life_Left\s+|Perc_Avail_Resrvd_Space\s+/i and $line =~ /(\d+)$/ ) {
		$smart->{$hddId}{pctRemaining} = $1;
	    }
	    elsif ( $line =~ /Available_Reservd_Space\s+/i and $line =~ /(\d+)$/ ) {
		$smart->{$hddId}{pctRemaining} = $1;
	    }
	    elsif ( $line =~ /Percent_Lifetime_Remain\s+/i and $line =~ /(\d+)$/ ) {
		$smart->{$hddId}{pctRemaining} = 100 - $1;
	    }
	    elsif ( $line =~ /Percentage used endurance indicator/i and $line =~ /(\d+)%$/ ) {
		$smart->{$hddId}{pctRemaining} = 100 - $1;
	    }
	    elsif ( $line =~ /Wear_Leveling_Count\s+/i ) {
		# looks dífferent for smartctl -a and smartctl -x
		if ( $line =~ /Wear_Leveling_Count\s+0x[0-9a-f]+\s+[0]*(\d+)\s/i ) {
		    $smart->{$hddId}{pctRemaining} = $1;
		} elsif ( $line =~ /Wear_Leveling_Count\s+[A-Z-]+\s+[0]*(\d+)\s/i ) {
		    $smart->{$hddId}{pctRemaining} = $1;
		}
	    }
	    elsif ( $line =~ /Media_Wearout_Indicator\s+/i and $line =~ /Media_Wearout_Indicator\s+0x[0-9a-f]+\s+[0]*(\d+)\s/ ) {
		$smart->{$hddId}{pctRemaining} = $1;
	    }
            elsif ( $line =~ /Media_Wearout_Indicator\s+/i and $line =~ /Media_Wearout_Indicator\s+.*\s+(\d+)$/ ) {
                $smart->{$hddId}{pctRemaining} = 100 - $1;
            }
	    if ( defined $smart->{$hddId}{transport} and $smart->{$hddId}{transport} =~ /[s]*ata/ ) {
                if ( $line =~ /Reallocated_Sector_Ct.+\s(\d+)$/i or $line =~ /Reallocate_NAND_Blk_Cnt.+\s(\d+)$/i ) {
                    $smart->{$hddId}{reallocSect} = $1;
                }
                elsif ( $line =~ /.+\sPower_On_Hours.+\s(\d+)$/i or $line =~ /.+\sPower_On_Hours.+\s(\d+)h[0-9\+ms\.]+$/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                }
		elsif ( $line =~ /.+\sPower_On_Hours.+\s(\d+)\s+\(\d+\s+\d+\s+\d+\)\s*$/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                }
                elsif ( $line =~ /.+\sPower_On_Minutes.+\s(\d+)h[0-9\+m\.]+$/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                }
                elsif ( $line =~ /.+\sAirflow_Temperature_Cel[^(]+\s(\d+)$/i ) {
                    $smart->{$hddId}{temp} = $1;
                }
                elsif ( $line =~ /.+\sAirflow_Temperature_Cel[^(]+\s(\d+)\s+\([^)]+\)\s*$/i ) {
                    $smart->{$hddId}{temp} = $1;
                }
                elsif ( $line =~ /.+\sTemperature_Celsius[^(]+\s(\d+)/i ) {
                    $smart->{$hddId}{temp} = $1;
                }
                elsif ( $line =~ /No\sErrors\sLogged$/i ) {
                    $smart->{$hddId}{numErr} = 0;
                }
                elsif ( $line =~ /ATA\sError\sCount:\s+(\d+).*$/i ) {
                    $smart->{$hddId}{numErr} = $1;
                }
                elsif ( $line =~ /CRC.Error.Count\s+.*\s(\d+)\s*$/i ) {
                    if ( undef $smart->{$hddId}{numErr} or not $smart->{$hddId}{numErr} or $smart->{$hddId}{numErr} == 0 ) {
                        $smart->{$hddId}{numErr} = $1;
                   }
                }
		elsif ( $line =~ /Current_Pending_Sector.*\s(\d+)$/i ) {
		    $smart->{$hddId}{pendsect} = $1;
		}
                elsif ( $line =~ /SATA\sVersion\sis.+\(current:\s+(\d+.+)\)$/i ) {
                    $smart->{$hddId}{ifSpeed} = $1;
                    $smart->{$hddId}{ifSpeed} =~ s/\.0//;
                }
                elsif ( $line =~ /SATA\sVersion\sis.+\s([0-9\.]+\s*Gb.s)/i ) {
                    $smart->{$hddId}{ifSpeed} = $1;
                    $smart->{$hddId}{ifSpeed} =~ s/\.0//;
                }
                elsif ( $line =~ /ATA\sVersion\sis.+ATAPI-7/i ) {
                    $smart->{$hddId}{ifSpeed} = "133MB/s";
                }
                elsif ( $line =~ /ATA\sVersion\sis.+ATAPI-6/i ) {
                    $smart->{$hddId}{ifSpeed} = "100MB/s";
                }
                elsif ( $line =~ /ATA\sVersion\sis.+ATAPI-5/i ) {
                    $smart->{$hddId}{ifSpeed} = "66.6MB/s";
                }
                elsif ( $line =~ /ATA\sVersion\sis.+ATAPI-4/i ) {
                    $smart->{$hddId}{ifSpeed} = "33.3MB/s";
                }
            } elsif ( defined $smart->{$hddId}{transport} and $smart->{$hddId}{transport} eq "sas" ) {
                if ( $line =~ /Elements\sin\sgrown\sdefect\slist:\s+(\d+)$/i ) {
                    $smart->{$hddId}{reallocSect} = $1;
                }
                elsif ( $line =~ /\s+number\sof\shours\spowered\sup\s=\s(\d+)/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                }
                elsif ( $line =~ /Accumulated\spower\son\stime,\shours:minutes\s([0-9]+):([0-9]+)/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                }
                elsif ( $line =~ /Current\sDrive\sTemperature:\s+(\d+)/i ) {
                    $smart->{$hddId}{temp} = $1;
                }
                elsif ( $line =~ /Total new blocks reassigned =\s+(\d+)$/i ) {
                    $smart->{$hddId}{pendsect} = $1;
                }
                elsif ( $line =~ /Non-medium\serror\scount:\s+(\d+)$/i ) {
                    $smart->{$hddId}{numErr} = $1;
                }
                elsif ( $line =~ /attached device type: no device attached/i ) {
		    $SASignoreNextIFSpeed = 1;
                }
                elsif ( $line =~ /attached device type:/i ) {
		    $SASignoreNextIFSpeed = 0;
                }
                elsif ( $line =~ /negotiated logical link rate:[^\d]+(\d.*)$/i and $SASignoreNextIFSpeed == 0 ) {
		    $smart->{$hddId}{ifSpeed} = ($smart->{$hddId}{ifSpeed} and $smart->{$hddId}{ifSpeed} eq $1) ? "$smart->{$hddId}{ifSpeed} 2x" : $1;
                }
	    } elsif ( defined $smart->{$hddId}{transport} and $smart->{$hddId}{transport} eq "nvme" ) {
                if ( $line =~ /^Temperature:\s+(\d+)/i ) {
                    $smart->{$hddId}{temp} = $1;
                }
                elsif ( $line =~ /^Power\sOn\sHours:\s+([0-9,]+)$/i ) {
                    $smart->{$hddId}{powOnHours} = $1;
                    $smart->{$hddId}{powOnHours} =~ s/,//g;
                }
                elsif ( $line =~ /^Available\s+Spare:\s+([0-9]+)%$/i ) {
                    $smart->{$hddId}{pctRemaining} = $1;
                }
                elsif ( $line =~ /^(\S+)\s+Errors Logged/i ) {
                    $smart->{$hddId}{numErr} = ( $1 eq "No" ) ? 0 : $1;
                }
            }
        }
	if ( not ( $smart->{$hddId}{vendor} or  $smart->{$hddId}{devModel} and  $smart->{$hddId}{serial} ) and ( $hddId !~ /nvme/i ) ) {
	    my $diskinfo = $hdd{$hddId}{descrip};
	    print "\nno basic information/unsupported disk $hddId ($diskinfo), omitting it\n";
	    delete $smart->{$hddId};
	    delete $hdd{$hddId};
	    next;
	}
#	if ( not defined $smart->{$hddId}{vendor} or not defined $smart->{$hddId}{devModel} or not defined $smart->{$hddId}{serial} ) {
#	    print "no basic information for $hddId\n";
#	    next;
#	}
#	if ( $smart->{$hddId}{vendor} eq "" and $smart->{$hddId}{devModel} eq "" and $smart->{$hddId}{serial} eq "" ) {
#	    print "no basic informations for $hddId\n";
#	    next;
#	}

	#
	# gather info about self encrypting drives
	#
	$smart->{$hddId}{has_cryProt} = 'n/a' until defined $smart->{$hddId}{has_cryProt};
	$smart->{$hddId}{cryProtAct} = 'n/a'  until defined $smart->{$hddId}{cryProtAct};

	# JBOD disks might get special treatment, even if accessed via a certain controller driver
	# for the following infos to gather it seems possible to access them like ahci disks

	my $controllerType = $ctrl{$host}{driver};

	if ( defined $hdd{$hddId}{JBOD} && $hdd{$hddId}{JBOD} == 1) {
	    # proactive: currently there is no way of getting these information from RAID member disks implemented
	    $controllerType = "ahci";
	    print "JBOD" if $main::verbose;
	}
        if ( defined $ctrlChoice2a{ $controllerType } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice2a{ $controllerType }->();
	    # if there are some slow SAS disks show activity
            print "'";
	    foreach my $line (@T10PI_Data) {
		#print $line if $main::Debug;
		chomp $line;
		if ( $line =~ /^\s+Protection:\s+prot_en=(\d),\s+p_type=(\d),\s+p_i_exponent=(\d)\s+\[type \d protection\]/i ) {
		    print "T10PI_Data A: \$1: $1 \$2: $2\n" if $main::debug;
		    $smart->{$hddId}{has_cryProt} = ( $1 != 0 or $2 != 0 ) ? 'yes' : 'no';
		    $smart->{$hddId}{cryProtAct} = 'yes';
		} elsif ($line =~ /^\s+Protection:\s+prot_en=(\d),\s+p_type=(\d)/i ) {
		    print "T10PI_Data B: \$1: $1 \$2: $2\n" if $main::debug;
		    $smart->{$hddId}{has_cryProt} = ( $1 != 0 or $2 != 0 ) ? 'yes' : 'no';
		    $smart->{$hddId}{cryProtAct} = 'no';
		}
	    }

        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver} for cryto check, please file a feature request for it.\n";
	}
	#
	# another way of detecting encrytion capabilities, esspecially for SSDs
	#
	# looks lile
	#
	## ...
	## Security:
	##         Master password revision code = 65534
	##                 supported
	##         not     enabled
	##         not     locked
	##         not     frozen
	##         not     expired: security count
	##                 supported: enhanced erase
	##         4min for SECURITY ERASE UNIT. 4min for ENHANCED SECURITY ERASE UNIT.
	## Logical Unit WWN Device Identifier: 55cd2e404c74eedf
	## ...
	#
	$smart->{$hddId}{cryOpt} = "";
	$smart->{$hddId}{cryEera} = "";
        if ( $smart->{$hddId}{transport} ne "sas" ) {
	    if ( defined $ctrlChoice2b{ $controllerType } ) {
		#print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
		$ctrlChoice2b{ $controllerType }->();
		# if there are some slow SAS disks show activity
		print ":";
		foreach my $line (@CRYPT_Data) {
		    #print $line if $main::Debug;
		    chomp $line;
		    if ( $line =~ /^Security:\s*$/ ) {
			$inSecurity++;
			print "\n" if $main::Debug;
			if ($inSecurity > 1 ) {
			    print "Disk $hddId: oops, inSecurity greater than 1, that's weired\n";
			}
		    } elsif ( $inSecurity == 1 ) {
			next if ( $line =~ /Master password revision code/ );	# ignored line
			if ( $line =~ /^\S/ ) {
			    # next chapter, end of Security chapter
			    $inSecurity = 0;
			} elsif ( $line =~ /\s+(not){0,1}\s*(supported)(.*)$/ ) {
			    # can or can not
			    if ( $securitySupported == 0 and ! defined $1 ) {
				$smart->{$hddId}{has_cryProt} = $smart->{$hddId}{has_cryProt} eq 'yes' ? 'yes' : 'avail';
				$securitySupported = 1;
			    } elsif ($securitySupported == 0 and defined $1 ) {
			        if ( $1 eq 'not' ) {
				    $smart->{$hddId}{has_cryProt} = $smart->{$hddId}{has_cryProt} eq 'no' ? 'NO' : 'No';
				} else {
				    print "Disk $hddId: weired security enabled line: $line\n";
				}
			    } elsif ( $securitySupported == 1 and defined $3 ) {
				# second line containing "supported", expected to report enhanced erase
				# print "disk $hddId: '$1' supported \$3: '$3'\n";
				if ( $3 eq ": enhanced erase" ) {
				    if ( ! defined $1 ) {
				        # we have enhanced erase
					$smart->{$hddId}{cryOpt} = "Eera";
				    } elsif ( $1 =~ /not/i ) {
				        $smart->{$hddId}{cryOpt} = "-";
				    } else {
				        print "Disk $hddId: weired security feature enhanced erase: $line\n";
				    }
				} else {
				    print "Disk $hddId: unexpected security supported line: $line\n";
				}
			    }
			} elsif ( $line =~ /\s+(not){0,1}\s*(enabled)(.*)$/ ) {
			    # print "enabled: $line\n";
			    if ( $securitySupported == 1 ) {
				if ( ! defined $1 ) {
				    $smart->{$hddId}{cryProtAct} = $smart->{$hddId}{cryProtAct} = 'yes' ? 'YES' : 'Yes';
				} elsif ( $1 =~ /not/i ) {
				    $smart->{$hddId}{cryProtAct} = $smart->{$hddId}{cryProtAct} = 'no' ? 'NO' : 'No';
				} else {
				    print "Disk $hddId: unexpected line for Security enabled: $line\n";
				}
			    } elsif ( ! defined $1 ) {
				# security not supported but enabled?
				print "Disk $hddId: security not supported but enabled? weired.\n";
			    } elsif ( $1 =~ /not/i ) {
				# that looks normal then
				next;
			    } else {
				print "Disk $hddId: unexpected line for Security enabled: $line\n";
			    }
			} elsif ( $line =~ /\s+(not){0,1}\s*(locked|frozen|expired)(.*)$/ ) {
			    next; # skip all this for now
#			    if (defined $3) {
#				if ( defined $1 ) {
#				    print "1: $1\t2: $2\t3: $3\n";
#				} else {
#				    print "1: \t2: $2\n";
#				}
#			    } else {
#				if ( defined $1 ) {
#				    print "1: $1\t2: $2\n";
#				} else {
#				    print "1: \t2: $2\n";
#				}
#			    }
			} elsif ( $line =~ /^\s*(\d+)min for SECURITY ERASE UNIT\./ ) {
			    $smart->{$hddId}{cryEera} = $1;
			    $smart->{$hddId}{cryOpt} = "Sera" if ($smart->{$hddId}{cryOpt} =~ "-"); 
			    if ( $line =~ /\.\s+(\d+)min for ENHANCED SECURITY ERASE UNIT\./ ) {
			        $smart->{$hddId}{cryEera} .= "/$1";
			    } # no else. that missing enhanced security erase time is quite possible
			} else {
			    next if ( $line =~ /^\s*$/ );
			    print "disk $hddId: other line: '$line'\n";
			}
		    }
		}

	    } else {
		print "Unimplemented Controller: $ctrl{$host}{driver} for cryto2 check, please file a feature request for it.\n";
	    }
	}

	#
	# info about Host Protected Areas
	#
	$smart->{$hddId}{HPA} = 'n/a' until defined $smart->{$hddId}{HPA};
        if ( defined $ctrlChoice3{ $controllerType } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice3{ $controllerType }->();
	    # if there are some slow SAS disks show activity
            print ",";
	    foreach my $line (@HPA_Data) {
		#print $line if $main::Debug;
		chomp $line;
		if ( $line =~ /^\s+max\ssectors\s+=\s+(\d+)\/(\d+),\s+HPA\sis\s(\S+abled)\s*/i ) {
		    print "HPA_Data A: \$1: $1 \$2: $2 \$3: $3\n" if $main::debug;
		    $smart->{$hddId}{HPAavail} = $1;
		    $smart->{$hddId}{HPAmax} = $2;
		    $smart->{$hddId}{HPA} = ( $3 =~ /enabled/i ) ? "yes" : "no";
		    if ( $smart->{$hddId}{HPAavail} and $smart->{$hddId}{HPAavail} != $smart->{$hddId}{HPAmax} ) {
			print "$hddId: HPAavail($smart->{$hddId}{HPAavail}) != HPAmax($smart->{$hddId}{HPAmax})\n"
		    }
		}
	    }
        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver} for HPA check, please file a feature request for it.\n";
	}

	#
	# info about Device Configuration Overlay
	#
	$smart->{$hddId}{DCO} = 'n/a' until defined $smart->{$hddId}{DCO};
        if ( defined $ctrlChoice4{ $controllerType } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice4{ $controllerType }->();
	    # if there are some slow SAS disks show activity
            print "`";
	    foreach my $line (@DCO_Data) {
		print "DCO: $line" if $main::Debug;
		chomp $line;
		if ( $line =~ /DCO Checksum verified/i ) {
		    $smart->{$hddId}{DCO} = "yes";
		} elsif ( $line =~ /DCO Revision: (0x[0-9a-z]+)/i ) {
		    $smart->{$hddId}{DCOrevision} = $1;
		} elsif ( $line =~ /Real max sectors: ([1-9][0-9]*)/i ) {
		    $smart->{$hddId}{DCOsectors} = $1;
		    if ( defined $smart->{$hddId}{HPAmax} and $smart->{$hddId}{HPAmax} > 1
						      and $smart->{$hddId}{DCOsectors} > 1 ) {
			if ( $smart->{$hddId}{HPAmax} != $smart->{$hddId}{DCOsectors} ) {
			    print "$hddId: HPAmax != DCOsectors\n" if $main::debug;
			} else {
			    print "$hddId: HPAmax == DCOsectors == $smart->{$hddId}{HPAmax}\n" if $main::debug;
			}
		    }
		}
	    }
	    if ( $smart->{$hddId}{DCO} eq "yes" ) {
	        print "DCO: $smart->{$hddId}{DCO}, DCOrevision: $smart->{$hddId}{DCOrevision}, DCOsectors: $smart->{$hddId}{DCOsectors}\n" if $main::debug;
	    }
        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver} for DCO check, please file a feature request for it.\n";
	}

    }
    # get bus speed for nvmes
    foreach my $cnvme ( @nvmedisks ) {
	my $cnvmen = $cnvme . "n1";
	my $pcipath = `readlink /sys/block/$cnvmen/device/device`;
	$pcipath =~ s/^[^:]+//;
	my @lsipciout = `lspci -vv -s $pcipath`;
	(my $result) = grep ( /LnkSta:/, @lsipciout );
	chomp $result;
	$result =~ s/^.*LnkSta:\s+Speed\s+(\d+)(\S+)\s+.*Width\s(x\d+).*$/$1 $2 $3/;
	$result =~ s/,//;
	$smart->{$cnvme}{ifSpeed} = $result;
    }
    print "\n";
}

#
# beautify some writings, prepare a nice output and handle multipath disks
#
sub consolidateDrives {
    my $smart = $_[0];
    my $formathelper = $_[1];

    my $disk;
    my $vendor;
    my $DPdiskcnt;	# found dual ported disks
    my @DPdisk;
    my $i;
    my $maxPaths = 1;
    my %uniqueVendorModelSerial;
    my %uniqueVendorModelSerialCnt;
    my @pathCntOccurence;
    my @pathIndexUsed;
    my $diskIdentifier;
    my %attribmap = (
	vendor      => "VENDOR",
	devModel    => "MODEL",
	serial      => "SERIAL",
	slotinfo    => "CT:C:E:Slot",
	firmware    => "FIRMWARE",
	cryOpt      => "CRYOPT",
	cryEera     => "CRYERA",
	ifSpeed     => "IFSPEED",
	reallocSect => "SECTORS",
	pendsect    => "PENDSECT",
	sectSize    => "SECTSIZE",
        numErr      => "ERRORS"
	);

    foreach $disk ( sort sortDiskNames keys %$smart ) {
	print "$disk " if ( $main::debug );
	# beautify Model, try to add missing Vendor
	if( not $smart->{$disk}{vendor} ) {
	    # no vendor detected, try to derive it from disk type
	    if ( exists $smart->{$disk}{devModel} ) { 
		    if ( $smart->{$disk}{devModel} =~ /ST[0-9]/ ) {
			$smart->{$disk}{vendor} = "Seagate";
		    } elsif ( $smart->{$disk}{devModel} =~ /TS[0-9]/ ) {
			$smart->{$disk}{vendor} = "Transcend";
		    } elsif ( $smart->{$disk}{devModel} =~ /(WDC|Samsung|Intel|ATP)/i ) {
			$smart->{$disk}{vendor} = $1;
		    } elsif ( $smart->{$disk}{devModel} =~ /(WD)/i ) {
			$smart->{$disk}{vendor} = $1;
		    } elsif ( $smart->{$disk}{devModel} =~ /(Micron)/i ) {
			$smart->{$disk}{vendor} = $1;
		    } elsif ( $smart->{$disk}{devModel} =~ /(Toshiba)/i ) {
			$smart->{$disk}{vendor} = $1;
		}
	    }
	}
	# beautify Vendor
	if( $smart->{$disk}{vendor} ) {
	    $vendor = $smart->{$disk}{vendor};
	    $vendor =~ s/.*Western Digital.*/WDC/i;
	    $vendor =~ s/.*Hitachi.*/Hitachi/i;
	    $vendor =~ s/.*Dell.*/Dell/i;
	    $vendor =~ s/.*Toshiba.*/Toshiba/i;
	    $vendor =~ s/.*Seagate.*/Seagate/i;
	    $vendor =~ s/.*Maxtor.*/Maxtor/i;
	    $vendor =~ s/Intel.*/Intel/i;
	    $vendor =~ s/.*Samsung based SSDs.*/Samsung/i;
	    $vendor =~ s/.*Marvell based SanDisk SSDs.*/SanDisk/i;
	    $vendor =~ s/.*SandForce Driven SSDs.*/SandForce/i;
	    $vendor =~ s/.*Crucial\/Micron.*SSD.*/Crucial\/Micron/i;
	    $vendor =~ s/.*WD Blue \/ Red \/ Green SSDs/WDC/i;
	    $vendor =~ s/.*Micron.*SSD.*/Micron/i;
	    $smart->{$disk}{vendor} = $vendor;
	    # shorten the model by a leading vendor string
	    $smart->{$disk}{devModel} =~ s/^$vendor[\s_]+//i;
	    $smart->{$disk}{devModel} =~ s/\s+$vendor$//i;
	}
	
        # get max length for vendor, devmodel, ...
	foreach my $attrib ( keys %attribmap ) {
	    if( not defined $smart->{$disk}{$attrib} ) {
	        $smart->{$disk}{$attrib} = "";
	    }
	    if( not defined $formathelper->{$attrib}) {
		$formathelper->{$attrib} = length( $attribmap{$attrib} ) >= length( $smart->{$disk}{$attrib} ) ?
		    length( $attribmap{$attrib} ) : length( $smart->{$disk}{$attrib} );
	    } elsif ( $formathelper->{$attrib} < length($smart->{$disk}{$attrib})) {
		$formathelper->{$attrib} = length($smart->{$disk}{$attrib});
	    }
	}
	$diskIdentifier = $smart->{$disk}{vendor}.$smart->{$disk}{devModel}.$smart->{$disk}{serial};
	$smart->{$disk}{diskIdentifier} = $diskIdentifier;
	if( exists $uniqueVendorModelSerial{$diskIdentifier}) {
	    # disk found another time
	    $uniqueVendorModelSerial{$diskIdentifier} .= ", $disk";
	    $uniqueVendorModelSerialCnt{$diskIdentifier} += 1;
	    # print "Disk $diskIdentifier re-found: $uniqueVendorModelSerial{$diskIdentifier}\n";
	    #@DPdisk = split( /, /,  $uniqueVendorModelSerial{$diskIdentifier} ) ;
	    #$maxPaths = (scalar @DPdisk) if( (scalar @DPdisk) > $maxPaths );
	    $maxPaths = $uniqueVendorModelSerialCnt{$diskIdentifier} if ( $uniqueVendorModelSerialCnt{$diskIdentifier}  > $maxPaths );
	} else {
	    $uniqueVendorModelSerial{$diskIdentifier} = $disk;
	    $uniqueVendorModelSerialCnt{$diskIdentifier} = 1;
	}
    }
    if ( $main::debug ) {
	print "\n";
	print Dumper($formathelper) if $main::Debug;
	print "maxPaths: $maxPaths\n";
    }
    $DPdiskcnt = 0;
    # choose one disk from the multipathed

    # first: histogram
    foreach $diskIdentifier ( keys %uniqueVendorModelSerial ) {
	$DPdiskcnt++;
	$pathCntOccurence[$uniqueVendorModelSerialCnt{$diskIdentifier}]++;
    }
    print "diskcnt: $DPdiskcnt\n" if ( $main::verbose or $main::debug );
    print Dumper(@pathCntOccurence) if $main::Debug;
    for ($i = 1; $i <= $maxPaths; $i++ ) {
	my $pCOi = (defined $pathCntOccurence[$i]) ? $pathCntOccurence[$i] : 0;
	print "pathcnt $i : $pCOi disks\n" if $main::debug;
    } 
    for ($i = 1; $i <= $maxPaths; $i++ ) {
	$DPdiskcnt = 0;
	foreach $diskIdentifier ( keys %uniqueVendorModelSerial ) {
	    if ($uniqueVendorModelSerialCnt{$diskIdentifier} == $i) {
		$DPdiskcnt++; # counts per # of paths
		if ( $i == 1) {
		    $pathIndexUsed[1]++;
		    next;
		}

		@DPdisk = split( /, /,  $uniqueVendorModelSerial{$diskIdentifier} );
		my $modul = $DPdiskcnt % $i; # this is the index for the disk we'll keep
		print "m: $modul " if ( $main::debug );
		#my $modul = $i - 1; # this is the index for the disk we'll keep
		$pathIndexUsed[$modul + 1] += 1;
		for (my $j = 0; $j < $i; $j++ ) {
		    next if ($j == $modul);  # keep this disk 
		    my $DPdisk = $DPdisk[$j];
		    print "deleting DP $DPdisk\n" if $main::debug;
		    delete $smart->{$DPdisk};
		}
	    }
	}
    }
    if ( $main::debug ) {
	for ($i = 1; $i <= $maxPaths; $i++ ) {
	    print "pathIndex $i used by $pathIndexUsed[$i] disks\n";
	} 
    }
}

# FARM is checked after consolidation of the disks to avoid unnecxcessary 
sub readFARMdata {
    my $smart      = $_[0];	# ptr to smart data structure
    my $smartctl74 = 0;

    # check version of smartctl as FARM check requires >= 7.4
    my @smartctlVersion = `smartctl --version`;
    foreach my $line (@smartctlVersion) {
	chomp $line;
	if ( $line =~ /^smartctl\s+(\d+\.\d+)\s+/ ) {
	    print "smartctl version: $1\n" if ( $main::verbose );
	    if ( $1 >= 7.4 ) {
	        $smartctl74 = 1;
            } else {
		print "smartctl version is below 7.4, so no FARM data available\n" if ( $main::verbose );
	    }
        }
    }
    return unless $smartctl74 == 1 ;

    print "starting FARM\n" if ( $main::debug );
    # smartctl -l farm /dev/sda

    foreach my $hddId ( sort sortDiskNames keys %$smart ) {
	my @FARMdata;

	if ( $smart->{$hddId}{vendor} !~ /seagate/i ) {
	    next;
	}

	my $lhddId = $smart->{$hddId}{lhddId};
	my $phddId = $smart->{$hddId}{phddId} ? $smart->{$hddId}{phddId} : "";
	my $shddId = $smart->{$hddId}{shddId};	# scsi name/id
	my $cntrlr = $smart->{$hddId}{cntrlr};

	my %ctrlChoice = (
            "ahci"          => sub { @FARMdata = `smartctl -l farm /dev/$lhddId` },
            "uas"           => sub { @FARMdata = `smartctl -l farm /dev/$lhddId` },
            "pata_jmicron"  => sub { @FARMdata = `smartctl -l farm /dev/$lhddId` },
            "nvme"          => sub { @FARMdata = `smartctl -l farm /dev/$lhddId` },
	    "usb-storage"   => sub { @FARMdata = `smartctl -l farm /dev/$shddId` },
            # not seen SAS disks on ahci, uas or nvme so -a seems sufficient
            # else -x to get interface speed for SAS drives
	    #"3w-9xxx"       => sub { @FARMdata = `smartctl -l farm -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa}` },
	    #"3w-sas"        => sub { @FARMdata = `smartctl -l farm -d 3ware,$hdd{$hddId}{id} /dev/$hddId` },
            "mptsas"        => sub { @FARMdata = `smartctl -l farm /dev/$shddId` },
            "mpt2sas"       => sub { @FARMdata = `smartctl -l farm /dev/$shddId` },
            "mpt3sas"       => sub { @FARMdata = `smartctl -l farm /dev/$shddId` },
            "megaraid_sas"  => sub { @FARMdata = `smartctl -l farm -d megaraid,$phddId /dev/$lhddId` },
            "aacraid"       => sub { @FARMdata = `smartctl -l farm $shddId` }
            # aacraid SAS does only work without -d sat. A solution for SATA and SAS still needs to be implemented.
        );
        if ( defined $cntrlr ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice{$cntrlr}->();	# here work gets done
	    # if there are some slow SAS disks show activity
            print "+";
        } else {
	    print "Unimplemented Controller: $cntrlr, please file a feature request for it.\n";
	    next;
	}
	my $FARMstate;  # general state
	my $PoH;	# PowerOnHours
	my $AssDate;	# Assembly Date

	my @FARMstate = grep ( /^FARM log .* not supported\s*/, @FARMdata ) ;
	if ( scalar (@FARMstate) ge 1 ) {
	    # Seagate disk without FARM data
	    print "-";
	    next;
	}
	my @PoH = grep ( /^\s+Power on Hours:\s+\d+\s*$/, @FARMdata );
	if ( scalar (@PoH) eq 1 ) {
	    ( $PoH ) = @PoH;
	    if ( $PoH =~ /^\s+Power on Hours:\s+(\d+)\s*$/ ) {
		$smart->{$hddId}{FARMpoh} = $1;
		$main::FARMAvailable++;
		print "disk $hddId PoH $1\n" if ( $main::debug );
	    }
	} else {
	    print "ambiguous FARM Power on Hours for $hddId\n";
	}
	my @AssDate = grep ( /^\s+Assembly Date \(YYWW\):/, @FARMdata );
	if ( scalar (@AssDate)  eq 1 ) {
	    ( $AssDate ) = @AssDate;
	    if ( $AssDate =~ /^\s+Assembly Date \(YYWW\):\s+(\d)(\d)(\d)(\d)\s*$/ ) {
		$AssDate = "$4$3/$2$1";
	    } elsif ( $AssDate =~ /^\s+Assembly Date \(YYWW\):\s*$/ ) {
		$AssDate = "not set";
	    } else {
		print "ambiguous FARM Assembly Date for $hddId: $AssDate\n";
		$AssDate = "weird";
	    }
	    $smart->{$hddId}{FARMassdate} = $AssDate;
	    $main::FARMAvailable++;
	    print "disk $hddId AssDate (WW/YY): $AssDate\n" if ( $main::debug );
	} else {
	    print "ambiguous FARM Assembly Date for $hddId\n";
	}

    }
    print "\n";
}

sub printSmartData {
    my $smart = $_[0];
    my $formathelper = $_[1];
    # original static version
    # my $outFormat =        "%-7s %-10s %-30s %-24s %-15s %-8s %-9s %-11s %-5s %-8s %-8s %-7s %-4s %-13s\n";
    # dynamic column width
    my $outFormat;

    $formathelper->{slotinfo} = 0 unless ( defined $formathelper->{slotinfo} );
    #$formathelper->{slotinfo} = 0;
    #$main::SlotInfoAvailable = 0;
    my $SlotHead = $main::SlotInfoAvailable ? "CT:C:E:Slot" : "";
    #$main::FARMAvailable = 0;
    my $FARMformat = $main::FARMAvailable ? "%-7s %-7s" : "%s%s";
    my $FARMpohHead = $main::FARMAvailable ? "FARMPOH" : "";
    my $FARMdomHead = $main::FARMAvailable ? "FARMDOM" : "";

    $outFormat = sprintf( "%%-7s %%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%-3s %%-3s %%-7s %%-6s %%-%ds %%-%ds %%-8s %%-9s %%-%ds %%-5s %%-%ds %%-8s %%-%ds %%-6s %s %%-4s %%-7s %%-%ds %%-%ds\n",
	$formathelper->{vendor}, $formathelper->{devModel}, $formathelper->{serial}, $formathelper->{slotinfo}, $formathelper->{firmware}, $formathelper->{cryOpt}, $formathelper->{cryEera},
	$formathelper->{ifSpeed}, $formathelper->{sectSize}, $formathelper->{reallocSect}, $FARMformat, $formathelper->{numErr}, $formathelper->{pendsect} );
    printf $outFormat, "DEVICE", "VENDOR", "MODEL", "SERIAL", $SlotHead, "FIRMWARE", "HPA", "DCO", "CRYPROT", "CRYACT", "CRYOPT", "CRYERA", "CAPACITY", "TRANSPORT",
		       "IFSPEED", "RPM", "SECTSIZE", "HEALTH", "SECTORS", "HOURS", $FARMpohHead, $FARMdomHead, "TEMP", "%REMAIN", "ERRORS", "PENDSECT";

    foreach my $disk ( sort sortDiskNames keys %$smart ) {

	printf $outFormat,
	    $disk,
	    defined $smart->{$disk}{vendor}       ? $smart->{$disk}{vendor}      : "",
	    defined $smart->{$disk}{devModel}     ? $smart->{$disk}{devModel}    : "",
	    defined $smart->{$disk}{serial}       ? $smart->{$disk}{serial}      : "",
	    (defined $smart->{$disk}{slotinfo}    && $main::SlotInfoAvailable) ? $smart->{$disk}{slotinfo} : "",
	    defined $smart->{$disk}{firmware}     ? $smart->{$disk}{firmware}    : "",
	    defined $smart->{$disk}{HPA}          ? $smart->{$disk}{HPA}         : "",
	    defined $smart->{$disk}{DCO}          ? $smart->{$disk}{DCO}         : "",
	    defined $smart->{$disk}{has_cryProt}  ? $smart->{$disk}{has_cryProt} : "",
	    defined $smart->{$disk}{cryProtAct}   ? $smart->{$disk}{cryProtAct}  : "",
	    defined $smart->{$disk}{cryOpt}       ? $smart->{$disk}{cryOpt}      : "",
	    defined $smart->{$disk}{cryEera}      ? $smart->{$disk}{cryEera}     : "",
	    defined $smart->{$disk}{capacity}     ? $smart->{$disk}{capacity}    : "",
	    defined $smart->{$disk}{transport}    ? $smart->{$disk}{transport}   : "",
	    defined $smart->{$disk}{ifSpeed}      ? $smart->{$disk}{ifSpeed}     : "",
	    defined $smart->{$disk}{rotation}     ? $smart->{$disk}{rotation}    : "",
	    defined $smart->{$disk}{sectSize}     ? $smart->{$disk}{sectSize}    : "",
	    defined $smart->{$disk}{health}       ? $smart->{$disk}{health}      : "",
	    defined $smart->{$disk}{reallocSect}  ? $smart->{$disk}{reallocSect} : "",
	    defined $smart->{$disk}{powOnHours}   ? $smart->{$disk}{powOnHours}  : "",
	    (defined $smart->{$disk}{FARMpoh}     && $main::FARMAvailable) ? $smart->{$disk}{FARMpoh}     : "",
	    (defined $smart->{$disk}{FARMassdate} && $main::FARMAvailable) ? $smart->{$disk}{FARMassdate} : "",
	    defined $smart->{$disk}{temp}         ? $smart->{$disk}{temp}        : "",
	    defined $smart->{$disk}{pctRemaining} ? $smart->{$disk}{pctRemaining}: "",
	    defined $smart->{$disk}{numErr}       ? $smart->{$disk}{numErr}      : "",
	    defined $smart->{$disk}{pendsect}     ? $smart->{$disk}{pendsect}    : "";
    }
}

sub printBadDisks {
    my $smart = $_[0];
    my %badDisks;
    foreach my $disk ( sort sortDiskNames keys %$smart ) {

        if ( defined $smart->{$disk}{health} and $smart->{$disk}{health} !~ /PASSED|OK/ ) {
            push @{$badDisks{$disk}}, "health $smart->{$disk}{health}";
        }
        elsif ( $smart->{$disk}{reallocSect} and $smart->{$disk}{reallocSect} > 0 ) {
            push @{$badDisks{$disk}}, "sectors $smart->{$disk}{reallocSect}";
        }
        if ( $smart->{$disk}{numErr} and $smart->{$disk}{numErr} > 0 ) {
            push @{$badDisks{$disk}}, "errors $smart->{$disk}{numErr}";
        }
    }

    print "\nBad disks:\n";
    my @errorlist = sort sortDiskNames keys %badDisks;
    foreach ( @errorlist ) {
	print "$_: ", join(", ", @{$badDisks{$_}}), "\n";
    }
    if ( scalar @errorlist == 0 ) {
        print "none.\n";
    }
}


1;
