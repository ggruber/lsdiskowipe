package readSmartData;
use strict;
use warnings;
use Data::Dumper;

sub sortDiskNames {
    my $deltal = length( $a ) - length( $b );
    return ($deltal ? $deltal : $a cmp $b);
}

sub readSmartData {
    my $smart          = $_[0];	# ptr to smart data structure
    my $uc_blacklist   = $_[1]; # ptr to unconditional blacklist
    my @controllerData = `lsscsi -H`;
    my @hddData        = `lsscsi -g`;
    my %hdd;
    my %ctrl;
    my $twa = 0;
    my $has_nvme = 0;
    my @nvmedisks;

    foreach my $line (@controllerData) {
        chomp $line;
        if ( $line =~ /\[(\d+)\]\s+(\S+)\s*/ ) {
            my $id     = $1;
            my $driver = $2;
            $ctrl{$id}{driver} = $driver;
            if ( $driver =~ /^3w-9xxx$/ ) {
                $ctrl{$id}{twa}     = $twa;
                my @twData =  `tw_cli \/c$id show`;
                $ctrl{$id}{twData}  = \@twData;
                $twa++;
            }
        } elsif ( $line =~ /^\[(N:\d+)\]/ ) {
            if ( not $has_nvme ) {
                $has_nvme = 1;
                if ( not `sh -c "which nvme"` ) {
		    die "required program \"nvme\" not found, run installer again";
		}
            }
	    my $id     = $1;
	    my $driver = "nvme";
            $ctrl{$id}{driver} = $driver;
	} else {
	    print "$line\n" if ( $main::verbose or $main::debug );
	}

    }
    foreach my $line (@hddData) {
        chomp $line;
        if ($line =~ /^\[(\d+):(\d+):(\d+):(\d+)\].*\/dev\/(sd\w+)\s+\/dev\/(\w+)\n?/) {
	    next if ( grep ( /^\/dev\/$5$/, @$uc_blacklist ) );  # omit uc blacklisted disks
            $hdd{$5}{host}    = $1;
            $hdd{$5}{channel} = $2;
            $hdd{$5}{id}      = $3;
            $hdd{$5}{lun}     = $4;
            $hdd{$5}{sata}    = $5;
            $hdd{$5}{scsi}    = $6;
        } elsif ($line =~ /^\[(N:\d+):(\d+):(\d+)\].*\/dev\/(nvme\w+)n1\s+\-\n?/) {
	    next if ( grep ( /^\/dev\/$4$/, @$uc_blacklist ) );  # omit uc blacklisted disks
	    $hdd{$4}{host}    = $1;
            $hdd{$4}{id}      = $2;
            $hdd{$4}{lun}     = $3;
	    $hdd{$4}{sata}    = $4;
	    $hdd{$4}{scsi}    = "";
	    push ( @nvmedisks, "$4" );
	}
    }
    foreach my $hddId ( sort sortDiskNames keys %hdd ) {
        my @smartData;
	my @T10PI_Data;
	my $SASignoreNextIFSpeed = 0;
        my $host       = $hdd{$hddId}{host};
	print "$hddId\{$host\} " if $main::debug;
        $hdd{$hddId}{blanked}   = 0;
        $hdd{$hddId}{erased}    = 0;
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

        my %ctrlChoice = (
            "ahci"          => sub { @smartData = `smartctl -a /dev/$hddId` },
            "uas"           => sub { @smartData = `smartctl -a /dev/$hddId` },
            "nvme"          => sub { @smartData = `smartctl -a /dev/$hddId` },
	    "usb-storage"   => sub { @smartData = `smartctl -a /dev/$hdd{$hddId}{scsi}` },
            # not seen SAS disks on ahci, uas or nvme so -a seems sufficient
            # else -x to get interface speed for SAS drives
            "3w-9xxx"       => sub { @smartData = `smartctl -x -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa}` },
            "3w-sas"        => sub { @smartData = `smartctl -x -d 3ware,$hdd{$hddId}{id} /dev/$hddId` },
            "mptsas"        => sub { @smartData = `smartctl -x /dev/$hdd{$hddId}{scsi}` },
            "mpt2sas"       => sub { @smartData = `smartctl -x /dev/$hdd{$hddId}{scsi}` },
            "megaraid_sas"  => sub { @smartData = `smartctl -x -d megaraid,$hdd{$hddId}{id} /dev/$hddId` },
            "aacraid"       => sub { @smartData = `smartctl -x $hdd{$hddId}{scsi}` }
            # aacraid SAS does only work without -d sat. A solution for SATA and SAS still needs to be implemented.
        );

	my %ctrlChoice2 = (
            "ahci"          => sub { @T10PI_Data = `sg_readcap -l /dev/$hddId` },
            "nvme"          => sub { @T10PI_Data = `sg_readcap -l /dev/$hddId` },
            "uas"           => sub { @T10PI_Data = `sg_readcap -l /dev/$hddId` },
	    "usb-storage"   => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$hddId}{scsi}` },
            "3w-9xxx"       => sub { @T10PI_Data = `sg_readcap -l -d 3ware,$hdd{$hddId}{twId} /dev/twa$ctrl{$host}{twa}` },
            "3w-sas"        => sub { @T10PI_Data = `sg_readcap -l -d 3ware,$hdd{$hddId}{id} /dev/$hddId` },
            "mptsas"        => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$hddId}{scsi}` },
            "mpt2sas"       => sub { @T10PI_Data = `sg_readcap -l /dev/$hdd{$hddId}{scsi}` },
            "megaraid_sas"  => sub { @T10PI_Data = `sg_readcap -l -d megaraid,$hdd{$hddId}{id} /dev/$hddId` },
            "aacraid"       => sub { @T10PI_Data = `sg_readcap -l $hdd{$hddId}{scsi}` }
        );

        
        if ( defined $ctrlChoice{ $ctrl{$host}{driver} } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice{ $ctrl{$host}{driver} }->();
	    # if there are some slow SAS disks show activity
            print ".";
        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver}, please file a feature request for it.\n";
	    next;
	}

        if ( defined $ctrlChoice2{ $ctrl{$host}{driver} } ) {
            #print "hddId: $hddId; id: $hdd{$hddId}{id}; twa: $ctrl{$host}{twa}; twId: $hdd{$hddId}{twId} host: $host\n";
            $ctrlChoice2{ $ctrl{$host}{driver} }->();
	    # if there are some slow SAS disks show activity
            print "'";
        } else {
	    print "Unimplemented Controller: $ctrl{$host}{driver}, please file a feature request for it.\n";
	    next;
	}

	$smart->{$hddId}{has_cryProt} = 'n/a' until defined $smart->{$hddId}{has_cryProt};
	$smart->{$hddId}{cryProtAct} = 'n/a'  until defined $smart->{$hddId}{cryProtAct};

        foreach my $line (@smartData) {
	    print $line if $main::debug;
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
                elsif ( $line =~ /.+\sAirflow_Temperature_Cel[^(]+\s(\d+)$/i ) {
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
                elsif ( $line =~ /UDMA.CRC.Error.Count\s+.*(\d+)\s*$/i ) {
                    if ( undef $smart->{$hddId}{numErr} or not $smart->{$hddId}{numErr} ) {
                        $smart->{$hddId}{numErr} = $1;
                   }
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
        foreach my $line (@T10PI_Data) {
	    print $line if $main::debug;
            chomp $line;
            if ( $line =~ /^\s+Protection:\s+prot_en=(\d),\s+p_type=(\d),\s+p_i_exponent=(\d)\s+\[type \d protection\]/i ) {
		print "A: \$1: $1 \$2: $2\n" if $main::debug;
		$smart->{$hddId}{has_cryProt} = ( $1 != 0 or $2 != 0 ) ? 'yes' : 'no';
		$smart->{$hddId}{cryProtAct} = 'yes';
            } elsif ($line =~ /^\s+Protection:\s+prot_en=(\d),\s+p_type=(\d)/i ) {
		print "B: \$1: $1 \$2: $2\n" if $main::debug;
		$smart->{$hddId}{has_cryProt} = ( $1 != 0 or $2 != 0 ) ? 'yes' : 'no';
		$smart->{$hddId}{cryProtAct} = 'no';
	    }
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
	firmware    => "FIRMWARE",
	ifSpeed     => "IFSPEED",
	reallocSect => "SECTORS",
	sectSize    => "SECTSIZE"
	);

    foreach $disk ( sort sortDiskNames keys %$smart ) {
	print "$disk " if ( $main::debug );
	# beautify Model, try to add missing Vendor
	if( not $smart->{$disk}{vendor} ) {
	    # no vendor detected, try to derive it from disk type
	    if ( $smart->{$disk}{devModel} =~ /ST[0-9]/ ) {
		$smart->{$disk}{vendor} = "Seagate";
	    } elsif ( $smart->{$disk}{devModel} =~ /(WD|Samsung|Intel)/i ) {
		$smart->{$disk}{vendor} = $1;
	    }
	}
	if( $smart->{$disk}{vendor} ) {
	    $vendor = $smart->{$disk}{vendor};
	    $vendor =~ s/.*Western Digital.*/WD/i;
	    $vendor =~ s/.*Hitachi.*/Hitachi/i;
	    $vendor =~ s/.*Dell.*/Dell/i;
	    $vendor =~ s/.*Toshiba.*/Toshiba/i;
	    $vendor =~ s/.*Seagate.*/Seagate/i;
	    $vendor =~ s/Intel.*/Intel/i;
	    $vendor =~ s/.*Samsung based SSDs.*/Samsung/i;
	    $vendor =~ s/.*Marvell based SanDisk SSDs.*/SanDisk/i;
	    $vendor =~ s/.*SandForce Driven SSDs.*/SandForce/i;
	    $vendor =~ s/.*Crucial\/Micron.*SSD.*/Crucial\/Micron/i;
	    $vendor =~ s/.*Micron.*SSD.*/Micron/i;
	    $smart->{$disk}{vendor} = $vendor;
	    # shorten the model by a leading vendor strings
	    $smart->{$disk}{devModel} =~ s/^$vendor[\s_]+//i;
	    $smart->{$disk}{devModel} =~ s/\s+$vendor$//i;
	}
	
        # get max length for vendor, devmodel, ...
	foreach my $attrib ( keys %attribmap ) {
	    if( not defined $smart->{$disk}{$attrib} ) {
	        $smart->{$disk}{$attrib} = "";
	    } else {
	        if( not defined $formathelper->{$attrib}) {
		    $formathelper->{$attrib} = length( $attribmap{$attrib} ) >= length( $smart->{$disk}{$attrib} ) ?
			length( $attribmap{$attrib} ) : length( $smart->{$disk}{$attrib} );
		} elsif ( $formathelper->{$attrib} < length($smart->{$disk}{$attrib})) {
		    $formathelper->{$attrib} = length($smart->{$disk}{$attrib});
		}
	    }
	}
	$diskIdentifier = $smart->{$disk}{vendor}.$smart->{$disk}{devModel}.$smart->{$disk}{serial};
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
	# print Dumper($formathelper);
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
    print Dumper(@pathCntOccurence) if $main::debug;
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

sub printSmartData {
    my $smart = $_[0];
    my $formathelper = $_[1];
    # original static version
    # my $outFormat =        "%-7s %-10s %-30s %-24s %-15s %-8s %-9s %-11s %-5s %-8s %-8s %-7s %-4s %-13s\n";
    # dynamic column width
    my $outFormat = sprintf( "%%-7s %%-%ds %%-%ds %%-%ds %%-%ds %%-7s %%-6s %%-8s %%-9s %%-%ds %%-5s %%-%ds %%-8s %%-%ds %%-7s %%-4s %%-7s %%-13s\n",
       $formathelper->{vendor}, $formathelper->{devModel}, $formathelper->{serial}, $formathelper->{firmware},
       $formathelper->{ifSpeed}, $formathelper->{sectSize}, $formathelper->{reallocSect} );
    printf $outFormat, "DEVICE", "VENDOR", "MODEL", "SERIAL", "FIRMWARE", "CRYPROT", "CRYACT", "CAPACITY", "TRANSPORT", "IFSPEED",
		       "RPM", "SECTSIZE", "HEALTH", "SECTORS", "HOURS", "TEMP", "%REMAIN", "ERRORS";

    foreach my $disk ( sort sortDiskNames keys %$smart ) {

        printf $outFormat,
          $disk,
          defined $smart->{$disk}{vendor}      ? $smart->{$disk}{vendor}      : "",
          defined $smart->{$disk}{devModel}    ? $smart->{$disk}{devModel}    : "",
          defined $smart->{$disk}{serial}      ? $smart->{$disk}{serial}      : "",
          defined $smart->{$disk}{firmware}    ? $smart->{$disk}{firmware}    : "",
          defined $smart->{$disk}{has_cryProt} ? $smart->{$disk}{has_cryProt} : "",
          defined $smart->{$disk}{cryProtAct}  ? $smart->{$disk}{cryProtAct}  : "",
          defined $smart->{$disk}{capacity}    ? $smart->{$disk}{capacity}    : "",
          defined $smart->{$disk}{transport}   ? $smart->{$disk}{transport}   : "",
          defined $smart->{$disk}{ifSpeed}     ? $smart->{$disk}{ifSpeed}     : "",
          defined $smart->{$disk}{rotation}    ? $smart->{$disk}{rotation}    : "",
	  defined $smart->{$disk}{sectSize}    ? $smart->{$disk}{sectSize}    : "",
          defined $smart->{$disk}{health}      ? $smart->{$disk}{health}      : "",
          defined $smart->{$disk}{reallocSect} ? $smart->{$disk}{reallocSect} : "",
          defined $smart->{$disk}{powOnHours}  ? $smart->{$disk}{powOnHours}  : "",
          defined $smart->{$disk}{temp}        ? $smart->{$disk}{temp}        : "",
          defined $smart->{$disk}{pctRemaining}? $smart->{$disk}{pctRemaining}: "",
          defined $smart->{$disk}{numErr}      ? $smart->{$disk}{numErr}      : "";
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
