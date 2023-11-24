#
#===============================================================================
#
#         FILE: writeLogXML.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 27.04.2016 23:53:45
#     REVISION: ---
#===============================================================================
package writeLog::XML;
use strict;
use warnings;
use POSIX qw/strftime/;
require XML::Simple qw(:strict);

sub writeXMLLog {
    $input = $_[0];
    $outputFile = $_[1];
    $output = {};
    $output->{report}{wipe_data}{description}{date} = strftime "%Y-%m-%d_%H:%M%S", localtime(time);
    #my $xs = XML::Simple->new();
    #my $xml = $xs->XMLout($hash);

}

