#!/usr/bin/perl
# Get a raw html list of places and prepare raw list entry for addition to %location_data in get-vcal2.pl

use Cwd;
use IO::File;

use strict;

$| = 1;

# Global vars
my $input = "";
my $output = ""; # unused

# Version history:
# 1.01 Initial implementation 13-Mar-2022
# 1.02 Fixed location parsing 13-Mar-2022
my $version = "1.01";

# 0 for normal operation
my $debug = 1;

# Parse command line options
parse_options(@ARGV);

# Invoke main
main();

sub main()
{
	die( "No --input=filename specified" ) unless ($input ne "");
	open( INPUT, "<$input" ) or die( "Failed to open $input: $!" );
	printf "# Raw entries for merging into location_data in get-vcal2.pl\n# Created by convert-places.pl v%s from %s\n", $version, $input;

	# Usage: run ./get-vcal-data.sh places-000.txt 0 place-list
	# then ./convert-places.pl --input=places-000.txt
	
	# Entry examples:
	# <option value="Romford, England, UK          000E11 51N35     +0.00" >Romford, England, UK          000E11 51N35     +0.00</option>
	# <option value="Santa Cruz de Tenerife, Spain 016W14 28N28     +0.00" >Santa Cruz de Tenerife, Spain 016W14 28N28     +0.00</option>
	# ...............0123456789|123456789|123456789|123456789|123456789|1
	#               (..............................)
	#                                             (......)\s(.....)\s+(\S+)
	# Length: 52
	# Expected output:
	# 	"UK-SW1A1AA" => [ "London, England, UK", "000W10", "51N30", "+0.00", "+0000", "Europe/London" ]


	my $value = "";
	my $count = 0;
	while (<INPUT>)
	{
		chomp;
		if ($_ =~ /<option value="([^"]+)"/)
		{
			$value = $1;
			my $cc = "XX";
			my $pc = "000000";
			if (length($value) eq 1) 
			{
				next;
			}
			if (length($value) ne 52)
			{
				printf "# Ignoring length %d: %s\n", length($value), $value;
				next;
			}
			if ($value =~ /(..............................)(......)\s(.....)\s+(\S+)/)
			{
				my $pn = $1;
				my $lon = $2;
				my $lat = $3;
				my $dtz = $4;
				$pn =~ s/\s+$//;
				my $tzs;
				my $tzt;
				my $tzf;
				my $tzhhmm = $dtz;
				my $dlat = latlontodec($lat);
				my $dlon = latlontodec($lon);
				my $url = sprintf("https://google.com/maps/@%f,%f,15z", $dlat, $dlon);
				if ($dtz =~ /(.)([^.]+)\.(\d+)/)
				{
					$tzs = $1;
					$tzt = $2;
					$tzf = $3;
					$tzhhmm = sprintf("%s%02d%02d", $tzs, $tzt, $tzf);
				}
				printf "#  \"%s-%s\" => [ \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"UTC\" ], # %s\n", $cc, $pc, $pn, $lon, $lat, $dtz, $tzhhmm, $url;
			}
			else
			{
				printf "####### Parse failed: %s\n", $value;
				next;
			}
			$count++;
		}
	}

	printf "# %d entries from %s\n", $count, $input;

	close( INPUT );
}

sub parse_options()
{
    my $opt;
    foreach $opt (@_)
    {
    	if ($opt =~ /--input=(.*)/)
    	{
    		$input = $1;
		next;
    	}
	if ($opt =~ /--output=(.*)/)
	{
		$output = $1;
		next;
	}
	die( "Unrecognized option $opt" );
    }
}

sub latlontodec()
{
	my $degrees;
	my $minutes;
	my $sign;
	if ($_[0] =~ /(\d+)([NSEWnsew])(\d+)/)
	{
		$degrees = $1;
		$minutes = $3;
		$sign = $2;
		my $r = $degrees + $minutes / 60.0;
		if ($sign eq "S" || $sign eq "s" || $sign eq "W" || $sign eq "w")
		{
			$r = -$r;
		}
		return $r;
	}
	return -1;
}
