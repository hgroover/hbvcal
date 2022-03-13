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

my $zip_hash = "";
my $cal_tz = "America/Los_Angeles"; # TZ= value to pass to date
# The timezone hhmm value calendar was calculated for - always ignores DST
# Format returned by date +'%z' - parsed out of Current location: line
# Juneau is America/Juneau - all other Pacific time locations are the same
my $cal_tzhhmm = ""; #"-0800"; 

# Lookup for tz to timezone codes
# Updated 11-Mar-2022 from full list
my %tcodelookup;
$tcodelookup{"+0000"} = "0"; # Greenwich Mean Time: London, Lisbon
$tcodelookup{"+0100"} = "1"; # Amsterdam, Berlin, Rome
$tcodelookup{"+0200"} = "2"; # Athens, Helsinki, Tel Aviv, Vilnius
$tcodelookup{"+0300"} = "3"; # Bagdad, Moscow, Nairobi, Riyadh
$tcodelookup{"+0330"} = "350"; # Teheran
$tcodelookup{"+0400"} = "4"; # Abu Dhabi, Tbilisi, Baku
$tcodelookup{"+0500"} = "5"; # Chelyabinsk, Ekaterinburg, Ufa
$tcodelookup{"+0530"} = "550"; # India
$tcodelookup{"+0545"} = "575"; # Nepal
$tcodelookup{"+0600"} = "6"; # Dhaka, Astana
$tcodelookup{"+0700"} = "7"; # Bangkok, Hanoi
$tcodelookup{"+0800"} = "8"; # Beijing, Kuala Lumpur, Perth, Taipei
$tcodelookup{"+0900"} = "9"; # Seoul, Tokyo
$tcodelookup{"+0930"} = "950"; # Adelaide
$tcodelookup{"+1000"} = "10"; # Brisbane, Hobart, Khabarovsk, Aust
$tcodelookup{"+1100"} = "11"; # Yuzhno-Sakhalinsk
$tcodelookup{"+1200"} = "12"; # Fiji, Marshall Islands, New Zealand
$tcodelookup{"-0100"} = "21"; # Azores
$tcodelookup{"-0300"} = "23"; # Buenos Aires
$tcodelookup{"-0330"} = "2350"; # Newfoundland
$tcodelookup{"-0345"} = "2375"; # Berbice
$tcodelookup{"-0400"} = "24"; # Atlantic, Caracas, Cochabamba, La Paz
$tcodelookup{"-0500"} = "25"; # Eastern
$tcodelookup{"-0600"} = "26"; # Central Time
$tcodelookup{"-0700"} = "27"; # Mountain Time
$tcodelookup{"-0800"} = "28"; # Pacific Time
$tcodelookup{"-1000"} = "210"; # Hawaii

# Defined location data. Now skipping sunrise-rss2.php, we get (0-3 are all from select dropdown, 4 is from zipcode db)
#  [0] = placename, e.g. "Austin, Texas, USA" (must match entries listed in placelist-*.txt)
#  [1] = longitude "097W41"
#  [2] = latitude "30N16"
#  [3] = tz digital "-6.00"
#  [4] = tzhhmm "-0600" (lcl_tz) (new)
#  [5] = tzregion "America/New_York" (new)
my %location_data = (
# 13-Mar-2022 - added many entries in timecode order + placename lexical order, which starts from 0 and goes east,
# then jumps to western timezones starting with 20
# Created by convert-places.pl v1.01 from places-000.txt
  "UK-B82QE" => [ "Birmingham, England, UK", "001W50", "52N30", "+0.00", "+0000", "Europe/London" ], # https://google.com/maps/@52.500000,-1.833333,15z
  "UK-BS16QF" => [ "Bristol, England, UK", "002W35", "51N27", "+0.00", "+0000", "Europe/London" ], # https://google.com/maps/@51.450000,-2.583333,15z
  "UK-CF142QQ" => [ "Cardiff, Wales, UK", "003W13", "51N30", "+0.00", "+0000", "Europe/London" ], # https://google.com/maps/@51.500000,-3.216667,15z
  "IE-9MX6G8" => [ "Dublin, Ireland", "006W20", "53N24", "+0.00", "+0000", "Europe/Dublin" ], # https://google.com/maps/@53.400000,-6.333333,15z
  "UK-SW1A1AA" => [ "London, England, UK", "000W10", "51N30", "+0.00", "+0000", "Europe/London" ], # https://google.com/maps/@51.500000,-0.166667,15z
# Created by convert-places.pl v1.01 from places-001.txt
  "NL-1094CC" => [ "Amsterdam, Netherlands", "004E57", "52N22", "+1.00", "+0100", "Europe/Amsterdam" ], # https://google.com/maps/@52.366667,4.950000,15z
  "RS-11060" => [ "Belgrade, Serbia", "020E30", "44N49", "+1.00", "+0100", "Europe/Belgrade" ], # https://google.com/maps/@44.816667,20.500000,15z
  "DE-13351" => [ "Berlin, Germany", "013E21", "52N33", "+1.00", "+0100", "Europe/Berlin" ], # https://google.com/maps/@52.550000,13.350000,15z
  "ES-19400" => [ "Brihuega, Spain", "002W52", "40N45", "+1.00", "+0100", "Europe/Madrid" ], # https://google.com/maps/@40.750000,-2.866667,15z
  "DE-80636" => [ "Munchen (Munich), Germany", "011E33", "48N09", "+1.00", "+0100", "Europe/Berlin" ], # https://google.com/maps/@48.150000,11.550000,15z
  "IT-80139" => [ "Naples (Napoli), Italy", "014E16", "40N52", "+1.00", "+0100", "Europe/Rome" ], # https://google.com/maps/@40.866667,14.266667,15z
  "FR-75014" => [ "Paris, France", "002E20", "48N50", "+1.00", "+0100", "Europe/Paris" ], # https://google.com/maps/@48.833333,2.333333,15z
  "IT-00195" => [ "Rome, Italy", "012E28", "41N55", "+1.00", "+0100", "Europe/Rome" ], # https://google.com/maps/@41.916667,12.466667,15z
  "SE-11451" => [ "Stockholm, Sweden", "018E05", "59N20", "+1.00", "+0100", "Europe/Stockholm" ], # https://google.com/maps/@59.333333,18.083333,15z
  "AT-1090" => [ "Vienna, Austria", "016E22", "48N13", "+1.00", "+0100", "Europe/Vienna" ], # https://google.com/maps/@48.216667,16.366667,15z
  "PL-00227" => [ "Warsaw, Poland", "021E00", "52N15", "+1.00", "+0100", "Europe/Warsaw" ], # https://google.com/maps/@52.250000,21.000000,15z
  "CH-6319" => [ "Zurich, Switzerland", "008E33", "47N10", "+1.00", "+0100", "Europe/Zurich" ], # https://google.com/maps/@47.166667,8.550000,15z
# Created by convert-places.pl v1.01 from places-550.txt
	"IN-741302" => [ "Navadwip, W. Bengal, India", "088E22", "23N25", "+5.30", "+0530", "Asia/Calcutta" ],
	"IN-110058" => [ "New Delhi, India", "077E12", "28N36", "+5.30", "+0530", "Asia/Calcutta" ],
	"IN-281121" => [ "Vrindavan, U.P., India", "077E42", "27N35", "+5.30", "+0530", "Asia/Calcutta" ],
# Created by convert-places.pl v1.01 from places-025.txt
	"US-32615" => [ "Alachua, Florida, USA", "082W30", "29N48", "-5.00", "-0500", "America/New_York" ],
	"US-32801" => [ "Orlando, Florida, USA", "081W23", "28N32", "-5.00", "-0500", "America/New_York" ],
	"US-33125" => [ "Miami, Florida, USA", "080W15", "25N47", "-5.00", "-0500", "America/New_York" ],
#	"US-34120" => [ "Naples, Florida, USA", "081W36", "26N17", "-5.00", "-0500", "America/New_York" ],
	"US-33607" => [ "Tampa, Florida, USA", "082W29", "27N59", "-5.00", "-0500", "America/New_York" ],
# Created by convert-places.pl v1.01 from places-026.txt
	"US-78721" => [ "Austin, Texas, USA", "097W41", "30N16", "-6.00", "-0600", "America/Chicago" ],
# Created by convert-places.pl v1.01 from places-028.txt	
    "US-95521" => [ "Arcata, California, USA", "124W05", "40N52", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-93641" => [ "Badger, CA", "119W01", "36N38", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-94702" => [ "Berkeley, California, USA", "122W17", "37N52", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-97405" => [ "Eugene, Oregon, USA", "123W08", "44N00", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-99801" => [ "Juneau, Alaska, USA", "134W30", "58N26", "-8.00", "-0900", "America/Juneau" ], # Lie! Juneau is GMT-9, not GMT-8
	"US-90023" => [ "Los Angeles, California, USA", "118W12", "34N00", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-97212" => [ "Portland, Oregon, USA", "122W38", "45N34", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-92105" => [ "San Diego, California, USA", "117W05", "32N45", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-94102" => [ "San Francisco, CA, USA", "122W25", "37N46", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-95050" => [ "San Jose, California, USA", "121W57", "37N22", "-8.00", "-0800", "America/Los_Angeles" ],
	"US-98112" => [ "Seattle, Washington, USA", "122W15", "47N37", "-8.00", "-0800", "America/Los_Angeles" ]
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
	die( "No --zip=zipcode specified" ) unless ($zip_hash ne "");

	die( "Location data not defined for zip $zip_hash" ) unless defined( @location_data{$zip_hash} );

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
	# Timezone format is hh.mm
	my $tzd = $tzval / 100.0;
	if ($tzval % 100 != 0)
	{
		$tzd = ($tzval - ($tzval % 100)) / 100.0 + ($tzval % 100) / 60.0;
		printf( "Converted %s to decimal %f\n", $tzval, $tzd );
	}
		# Formatted location was used with a previous calendar version that allowed ad-hoc
		# lat/lon. Now a tzcode and formatted location matching existing list entries must
		# be used.
		my $prefixed_tz = sprintf("%.2f", $tzval / 100);
		if ($tzval >= 0)
		{
			$prefixed_tz = sprintf("+%s", $prefixed_tz);
			printf( "Prefixed %.2f to %s\n", $tzval / 100, $prefixed_tz );
		}
		else
		{
			printf( "Prefixed %.2f to %s :: %d >= 0 (already signed negative)\n", $tzval / 100, $prefixed_tz, $tzval );
		}
		my $location_fmt = sprintf( "%-29.29s %-6.6s %-5.5s %9s",
			$placename, $geo_hmlon, $geo_hmlat, $prefixed_tz );
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
		#printf( "parse %s\n", $opt );
    	if ($opt =~ /--zip=(.*)/)
    	{
    		$zip_hash = $1;
			#printf( "got zip_hash %s\n", $zip_hash );
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

