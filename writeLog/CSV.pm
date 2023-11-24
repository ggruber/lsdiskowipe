#
#===============================================================================
#
#         FILE: writeLogCSV.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 28.04.2016 09:11:52
#     REVISION: ---
#===============================================================================
package writeLog::CSV;
use strict;
use warnings;
use Text::CSV;

sub writeLog {
    my $smartData = $_[0];
    my $outputFile = $_[1];

    my $csv = Text::CSV->new ( {eol => "\r\n",sep_char => ';'} ) or die "Cannot use CSV: ".Text::CSV->error_diag();
    open my $fh, ">:encoding(utf8)", "$outputFile.csv" or die $!;
    foreach my $hddId (sort keys $smartData) {
        my @line = ($smartData->{$hddId}{vendor},
                    $smartData->{$hddId}{model},
                    $smartData->{$hddId}{serial},
                    $smartData->{$hddId}{firmware},
                    $smartData->{$hddId}{capacity},
                    $smartData->{$hddId}{transport},
                    $smartData->{$hddId}{health},
                    $smartData->{$hddId}{temp},
                    $smartData->{$hddId}{reallocSect},
                    $smartData->{$hddId}{reallocSectAE},
                    $smartData->{$hddId}{numErr},
                    $smartData->{$hddId}{powOnHours},
                    $smartData->{$hddId}{eraseDate},
                    $smartData->{$hddId}{eraseTime},
                    $smartData->{$hddId}{method},
                    $smartData->{$hddId}{roundsToDo},
                    $smartData->{$hddId}{roundsDone},
                    $smartData->{$hddId}{blanked},
                    $smartData->{$hddId}{erased});

        $csv->print($fh, \@line);
        }
        close $fh;

}
return 1;
