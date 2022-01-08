#!/usr/bin/perl
# Get vcal data for a US zipcode
# Updated get-vcal2.pl does not rely on http://henrygroover.net/sunrise-rss2.php
# See update-process.txt for usage and for adding new location data

use DBI;
use Mail::Sendmail;
use MIME::QuotedPrint;
use MIME::Base64;
use Cwd;
use IO::File;
use Date::Format;
use Date::Parse;

use strict;

$| = 1;

# Global vars
my $input = "";
my $output = "vcal.ics";
my $min_date = "20101201";
my $max_date = "20111231";

my $zip_hash = 0;
my $cal_tz = "America/Los_Angeles"; # TZ= value to pass to date
# The timezone hhmm value calendar was calculated for - always ignores DST
# Format returned by date +'%z' - parsed out of Current location: line
# Juneau is America/Juneau - all other Pacific time locations are the same
my $cal_tzhhmm = ""; #"-0800"; 

# Lookup for tz to zoneinfo name
my %tzlookup;
# Avoid Arizona, Indiana, Kentucky and other sticky areas for now
$tzlookup{"USA-0900"} = "America/Juneau";
$tzlookup{"USA-0800"} = "America/Los_Angeles";
$tzlookup{"USA-0600"} = "America/Chicago";
$tzlookup{"USA-0500"} = "America/New_York";

# Lookup for tz to timezone codes
my %tcodelookup;
$tcodelookup{"-0500"} = "25";
$tcodelookup{"-0600"} = "26";
$tcodelookup{"-0700"} = "27";
$tcodelookup{"-0800"} = "28";

# Defined location data. Now skipping sunrise-rss2.php, we get (0-3 are all from select dropdown, 4 is from zipcode db)
#  [0] = placename, e.g. "Austin, Texas, USA" (must match entries listed in placelist-*.txt)
#  [1] = longitude "097W41"
#  [2] = latitude "30N16"
#  [3] = tz digital "-6.00"
#  [4] = tzhhmm "-0600" (lcl_tz) (new)
#  [5] = tzregion "America/New_York" (new)
my %location_data = (
	"95521" => [ "Arcata, California, USA", "124W05", "40N52", "-8.00", "-0800", "America/Los_Angeles" ],
	"93641" => [ "Badger, CA", "119W01", "36N38", "-8.00", "-0800", "America/Los_Angeles" ],
	"94702" => [ "Berkeley, California, USA", "122W17", "37N52", "-8.00", "-0800", "America/Los_Angeles" ],
	"97405" => [ "Eugene, Oregon, USA", "123W08", "44N00", "-8.00", "-0800", "America/Los_Angeles" ],
	"99801" => [ "Juneau, Alaska, USA", "134W30", "58N26", "-8.00", "-0900", "America/Juneau" ], # Lie! Juneau is GMT-9, not GMT-8
	"90023" => [ "Los Angeles, California, USA", "118W12", "34N00", "-8.00", "-0800", "America/Los_Angeles" ],
	"97212" => [ "Portland, Oregon, USA", "122W38", "45N34", "-8.00", "-0800", "America/Los_Angeles" ],
	"92105" => [ "San Diego, California, USA", "117W05", "32N45", "-8.00", "-0800", "America/Los_Angeles" ],
	"94102" => [ "San Francisco, CA, USA", "122W25", "37N46", "-8.00", "-0800", "America/Los_Angeles" ],
	"95050" => [ "San Jose, California, USA", "121W57", "37N22", "-8.00", "-0800", "America/Los_Angeles" ],
	"98112" => [ "Seattle, Washington, USA", "122W15", "47N37", "-8.00", "-0800", "America/Los_Angeles" ],
	"78721" => [ "Austin, Texas, USA", "097W41", "30N16", "-6.00", "-0600", "America/Chicago" ],
	"32615" => [ "Alachua, Florida, USA", "082W30", "29N48", "-5.00", "-0500", "America/New_York" ],
	"33125" => [ "Miami, Florida, USA", "080W15", "25N47", "-5.00", "-0500", "America/New_York" ],
#	"34120" => [ "Naples, Florida, USA", "081W36", "26N17", "-5.00", "-0500", "America/New_York" ],
	"33607" => [ "Tampa, Florida, USA", "082W29", "27N59", "-5.00", "-0500", "America/New_York" ]
);

# Timezone location exceptions
my %tzdata_exceptions = (
	"99801" => "America/Juneau"
);

# Parse command line options
parse_options(@ARGV);

# Invoke main
main();

sub main()
{
	die( "No --zip=zipcode specified" ) unless ($zip_hash != 0);

	die( "Location data not defined" ) unless defined( @location_data{$zip_hash} );

#wget -O - http://henrygroover.net/sunrise-rss2?zip=$1 returns
#...
#<lcl_place>Oxnard, CA USA</lcl_place>
#<lcl_state>CA</lcl_state>
#<lcl_county>Ventura</lcl_county>
#<lcl_city>Oxnard</lcl_city>
#<lcl_country>USA</lcl_country>
#<lcl_tz>-0800</lcl_tz>
#<lcl_dst>0</lcl_dst>
#<lcl_lat>34N12'54</lcl_lat>
#<lcl_lon>119W10'48</lcl_lon>
#<lcl_geo>LAT 34N12 34.215000 LON 119W10 -119.180000</lcl_geo>
# We were using lcl_place, lcl_country, lcl_tz and lcl_geo
# Now we're getting $location_data{$zip_hash}[0] for lcl_place contents;
# we don't need country as we're now skipping tzlookup and getting the
# America/New_York etc. code from $location_data{$zip_hash}[5];
# lcl_tz is now available as $location_data{$zip_hash}[4];
# and the geo_dlat / geo_dlon values can be parsed from
# $location_data{$zip_hash}[2] and [1].

	my $placename = $location_data{$zip_hash}[0];
	my $country = "USA";
	my $tzval = $location_data{$zip_hash}[4];
	my $geo_hmlat = $location_data{$zip_hash}[2];
	my $geo_hmlon = $location_data{$zip_hash}[1];
	my $geo_dlat = hmtodegrees( $geo_hmlat );
	my $geo_dlon = hmtodegrees( $geo_hmlon );

	# Determine defaults for min date and max date
	my $cur_year = `date +'%Y'`;
	my $cur_month = `date +'%m'`;
	# Default to first of current month to last of previous month + 1 year
	$min_date = time2str( "%Y%m01", time() );
	my $timelast = str2time( sprintf("%04d-%02d-01 12:00:00", $cur_year + 1, $cur_month ) ) - 86400;
	$max_date = time2str( "%Y%m%d", $timelast );

	# Actual return may start with first of previous month and will never cover more than 12 months...
	printf( "Place: [%s]\n", $placename );
	printf( "TZ: [%s]\n", $tzval );
	printf( "Coords: %s %s (%s %s)\n", $geo_hmlat, $geo_hmlon, $geo_dlat, $geo_dlon );
	#<lcl_geo>LAT 34N12 34.215000 LON 119W10 -119.180000</lcl_geo>
	$cal_tz = $location_data{$zip_hash}[5];
	$cal_tzhhmm = $tzval;

	die( "No tcodelookup" ) unless defined( $tcodelookup{$tzval} );
	printf( "Timezone code[%s] = %s\n", $tzval, $tcodelookup{$tzval} );
	# FIXME Check for timezone format - is it decimal hours or hh.mm
	my $tzd = $tzval / 100.0;
	if ($tzval % 100 != 0)
	{
		die( "Unsure of decimal timezone format on $tzval" );
	}
		# Formatted location was used with a previous calendar version that allowed ad-hoc
		# lat/lon. Now a tzcode and formatted location matching existing list entries must
		# be used.
#TIMEZONE=28
#LOCATION="Los Angeles, California, USA  118W12 34N00     -8.00"
###########          1    1    2    2    3    3    4    4    55
###########01234567890    5    0    5    0    5    0    5    01
# This no longer works, only specific locations are supported. Added columns show lat long in digital format and closest zipcode
#LOCATION="Arcata, California, USA       124W05 40N52     -8.00"	-124.08333 40.866667	95521 (McKinleyville)
#LOCATION="Ashcroft, B.C., Canada        121W18 50N49     -8.00"
#LOCATION="Badger, CA                    119W01 36N38     -8.00"	-119.01667  36.633333	93641 (Miramonte)
#LOCATION="Berkeley, California, USA     122W17 37N52     -8.00"	-122.28333  37.866667	94702
#LOCATION="Eugene, Oregon, USA           123W08 44N00     -8.00"	-123.13333  44.000000	97405
#LOCATION="Juneau, Alaska, USA           134W30 58N26     -8.00"	-134.50000  58.433333	99801
#LOCATION="Los Angeles, California, USA  118W12 34N00     -8.00"	-118.20000  34.000000	90023
#LOCATION="Palo Alto, California, USA    122W10 37N28     -8.00"
#LOCATION="Pinehurst, CA                 119W01 36N42     -8.00"
#LOCATION="Portland, Oregon, USA         122W38 45N34     -8.00"	-122.63333  45.566667	97212
#LOCATION="San Diego, California, USA    117W05 32N45     -8.00"	-117.08333  32.750000	92105
#LOCATION="San Francisco, CA, USA        122W25 37N46     -8.00"	-122.41667  37.766667	94102
#LOCATION="San Jose, California, USA     121W57 37N22     -8.00"	-121.95000  37.366667	95050 (Santa Clara)
#LOCATION="Seattle, Washington, USA      122W15 47N37     -8.00"	-122.25000  47.616667	98112
#LOCATION="Tijuana, Mexico               117W01 32N32     -8.00"
#LOCATION="Vancouver, Canada             122W57 49N08     -8.00"
#LOCATION="Victoria, Canada              123W19 48N18     -8.00"
#LOCATION="Walla Walla, Washington, USA  118W18 46N05     -8.00"

		my $location_fmt = sprintf( "%-29.29s %-6.6s %-5.5s %9.2f",
			$placename, $geo_hmlon, $geo_hmlat, $tzval / 100.0 );
		my $data_dir = ".vcal-data";
		if (-d $data_dir)
		{
			printf( "%s already exists\n", $data_dir );
		}
		else
		{
			printf( "Creating %s\n", $data_dir );
			mkdir( $data_dir ) or die( "Failed to create $data_dir" );
		}
		my $raw_data = sprintf( "%s/%s-%s-%s.raw", $data_dir, $zip_hash, $min_date, $max_date );
		if (-r $raw_data)
		{
			printf( "Raw data already exists in %s\n", $raw_data );
		}
		else
		{
			my $cmd = sprintf( "./get-vcal-data.sh %s %s \"%s\"",
				$raw_data, $tcodelookup{$tzval}, $location_fmt );
			printf( "Running %s\n", $cmd );
			`$cmd`;
		}
		# FIXME Figure out the range of applicable dates
		my $ics_data = sprintf( "%s/%s-%s-%s.ics", $data_dir, $zip_hash, $min_date, $max_date );
		my $txt_data = sprintf( "%s/%s-%s-%s.txt", $data_dir, $zip_hash, $min_date, $max_date );
		if (-r $ics_data && -r $txt_data)
		{
			printf( "Text and ics data exist: %s, %s\n", $ics_data, $txt_data );
		}
		else
		{
			# New format fails: test with
			# ./parse-vcal.pl --input=.vcal-data/92101.raw --output=.vcal-data/92101.ics --ziphash=92101 --caltz=America/Los_Angeles --caltzhhmm=-0800 --min-date=20111201 --max-date=20121201 > .vcal-data/92101.txt
			my $cmd = sprintf( "./parse-vcal.pl --input=%s --output=%s --ziphash=%s --caltz=%s --caltzhhmm=%s --min-date=%s --max-date=%s > $txt_data",
				$raw_data, $ics_data, $zip_hash, $cal_tz, $cal_tzhhmm, $min_date, $max_date );
			printf( "Running %s\n", $cmd );
			`$cmd`;
		}
}

# Convert ddNmm or dddEmm to signed digital degrees
sub hmtodegrees()
{
    my ($hhmm) = @_;
    if ($hhmm =~ /(\d\d)([NS])(\d\d)/)
    {
	my $d = $1 + $3 / 60.0;
	if ($2 eq "S")
	{
		$d = -$d;
	}
	return $d;
    }
    if ($hhmm =~ /(\d\d\d)([EW])(\d\d)/)
    {
	my $d = $1 + $3 / 60.0;
	if ($2 eq "W")
	{
		$d = -$d;
	}
	return $d;
    }
    die( "Failed to convert $hhmm" );
    return 0;
}

sub parse_options()
{
    my $opt;
    foreach $opt (@_)
    {
    	if ($opt =~ /--zip=(.*)/)
    	{
    		$zip_hash = $1;
		next;
    	}
	if ($opt =~ /--output=(.*)/)
	{
		$output = $1;
		next;
	}
	if ($opt =~ /--min-date=(.*)/)
	{
		$min_date = $1;
		next;
	}
	if ($opt =~ /--max-date=(.*)/)
	{
		$max_date = $1;
		next;
	}
	if ($opt =~ /--caltz=(.*)/)
	{
		$cal_tz = $1;
		next;
	}
	if ($opt =~ /--caltzhhmm=(.*)/)
	{
		$cal_tzhhmm = $1;
		next;
	}
	die( "Unrecognized option $opt" );
    }
}

# Get signed minute offset from GMT for a timedate
sub timedate_to_gmtoffset_minutes()
{
	my ($y, $m, $d, $h, $min) = @_;
	my $ymd = sprintf( "%04d-%02d-%02d %02d:%02d", $y, $m, $d, $h, $min );
	my $dtz = `TZ=$cal_tz date --date="$ymd" +'%z'`;
	return tzhhmm_to_minutes( $dtz );
}

# Convert +/-hhmm time zone to signed minutes, e.g. -0800 (PST) -> -480
sub tzhhmm_to_minutes()
{
	my ($hhmm_arg) = @_;
	if ($hhmm_arg =~ /(\S)(\d\d)(\d\d)/)
	{
		my $minutes = $2 * 60 + $3;
		if ($1 eq "-")
		{
			$minutes = -$minutes;
		}
		return $minutes;
	}
	else
	{
		printf( "tzhhmm_to_minutes(%s) did not match [.]hh.mm\n", $hhmm_arg );
	}
	return -1;
}

# Add minutes to time in HHMM format, and return new time. No date wrap supported
sub add_minutes_to_hhmm()
{
	my ($hhmm, $offset) = @_;
	$hhmm =~ /(\d\d)(\d\d)/;
	my $minutes = $2;
	my $hours = $1;
	$minutes += $offset;
	while ($minutes >= 60)
	{
		$hours++;
		$minutes -= 60;
	}
	while ($minutes < 0)
	{
		$hours--;
		$minutes += 60;
	}
	return sprintf( "%02d%02d", $hours, $minutes );
}

# Add minutes to time in HH:MM format, and return new time. No date wrap supported
sub add_minutes_to_hhcmm()
{
	my ($hhmm, $offset) = @_;
	$hhmm =~ /(\d\d):(\d\d)/;
	my $minutes = $2;
	my $hours = $1;
	$minutes += $offset;
	while ($minutes >= 60)
	{
		$hours++;
		$minutes -= 60;
	}
	while ($minutes < 0)
	{
		$hours--;
		$minutes += 60;
	}
	return sprintf( "%02d:%02d", $hours, $minutes );
}

