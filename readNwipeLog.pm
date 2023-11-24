#
#===============================================================================
#
#         FILE: readNwipeLog.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 27.04.2016 16:39:16
#     REVISION: ---
#===============================================================================
package readNwipeLog;
use strict;
use warnings;

sub readLog {
    my $smartData = $_[0];
    my $logFile = $_[1];
    # log file my be missing if nwipe crashed !!
    open FILE, $logFile or die $!;
    my @logFile = <FILE>;
    close FILE;
    
    foreach my $line (@logFile) {
        if ($line =~ /Invoking method '(.+)' on device '\/dev\/(\w+)'/) {
            my $method = $1;
            my $hddId = $2;
            if (defined $smartData->{$hddId}) {
                $smartData->{$hddId}{method} = $method;
            }
        }
        if ($line =~ /Verified that '\/dev\/(\w+)' is empty/) {
            if (defined $smartData->{$1}) {
                $smartData->{$1}{blanked} = 1;
            }
        }
        if ($line =~ /(\d+) bytes written to device '\/dev\/(\w+)'/) {
            if(defined $smartData->{$2}) {
                $smartData->{$2}{bytesWritten} = $1;
            }
        }
        if ($line =~ /Finished round (\d+) of (\d+) on device '\/dev\/(\w+)'/) {
            if(defined $smartData->{$3}) {
                $smartData->{$3}{roundsDone} = $1;
                $smartData->{$3}{roundsToDo} = $2;

                if($1 eq $2) {
                    $smartData->{$3}{erased} = 1;
                }
            }
        }
    }
}
return 1;
