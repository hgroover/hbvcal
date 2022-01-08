#!/usr/bin/perl
# parse raw html calendar

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
my $min_date = "20101208";
my $max_date = "20101231";
# Version history:
# 1.09 Updated 19-Dec-2013 to handle format changes
# 1.10 Updated 31-Mar-2019, more format changes (Current location -> Current Location)
# 1.11 Updated 02-Jan-2022, more format changes
my $version = "1.11";
my $entry_hash = 0x51070108;
# 0 for normal operation
my $debug = 1;

my $zip_hash = 92026;
my $cal_tz = "America/Los_Angeles"; # TZ= value to pass to date
# The timezone hhmm value calendar was calculated for - always ignores DST
# Format returned by date +'%z' - parsed out of Current location: line
my $cal_tzhhmm = ""; #"-0800"; 

# Parse command line options
parse_options(@ARGV);

# Invoke main
main();

sub main()
{
	die( "No --input=filename specified" ) unless ($input ne "");
	open( INPUT, "<$input" ) or die( "Failed to open $input: $!" );
	open( OUTPUT, ">$output" ) or die( "Failed to create $output: $!" );
	printf OUTPUT "BEGIN:VCALENDAR\nVERSION:%.1f\n", 2.0;
	printf OUTPUT "PRODID:-//NarayanaAyurvedaYoga LLC/vcal//NONSGML v%s//EN\n", $version;

	# State
	my $has_current_loc = 0;
	my $current_location = "";
	my $current_location_stripped = "";
	my $current_lat = "";
	my $current_long = "";
	my $current_city = "";
	my $current_state = "";
	my $current_country = "";
	my $masa = "";
	my $gaurabda = "";
	my $calver = "";
	my $paksa = "";
	my $tithi = "";
	my $tithi_ef = "";
	my $tithi_et = "";
	my $sunset = "";
	my $tithi_dstart = "";
	my $tithi_visible = 0;
	my $naksatra = "";
	my $sunrise = "";
	my $date = "";
	my $dow = "";
	my $month_changed = 0;
	my $tithi_open = 0;
	my $tithi_shows_month_change = 0;
	my $uid = 1000;
	my $day_event_idx = 0;
	my $vevent = "";
	my $vevent_uid = "";
	my $vevent_summary = "";
	my $vevent_dtstart = "";
	my $vevent_dtend = "";
	my $vtext = "";
	my $vtext_summary = "";
	my $min_events = 1;
	my $has_fast = 0;
	my $was_dst = -1;
	my $is_dst = -1;
	my $ltzm = 0;
	my $gmtoff = 0;
	if ($cal_tzhhmm ne "")
	{
		$ltzm = tzhhmm_to_minutes( $cal_tzhhmm );
	}
	while (<INPUT>)
	{
		chomp;
		if (!$has_current_loc)
		{
			if ($_ =~ /<strong> +[Cc]urrent [Ll]ocation: (.*)<\/strong>/)
			{
				$has_current_loc = 1;
				$current_location = $1;
				$current_location_stripped = $current_location;
				$current_location_stripped =~ s/\s+/ /g;
				my $tzew;
				my $tzh;
				my $tzm;

				# Previous regex here used (\S+) for city and state, failed on San Diego, California, USA and New York, New York, USA
				if ($current_location_stripped =~ /(.+),\s*(\S+),\s*(.+)\s+(\S+)\s+(\S+)\s+(\S)(\d+)\.(\d\d)/)
				{
					$current_city = $1;
					$current_state = $2;
					$current_country = $3;
					$current_long = $4;
					$current_lat = $5;
					$tzew = $6;
					$tzh = $7;
					$tzm = $8;
					if ($cal_tzhhmm eq "")
					{
						$cal_tzhhmm = sprintf( "%s%02d%02d", $tzew, $tzh, $tzm );
						$ltzm = tzhhmm_to_minutes( $cal_tzhhmm );
					}
					if ($current_country ne "USA")
					{
						$current_location_stripped = "$current_city, $current_state, $current_country";
					}
					else
					{
						$current_location_stripped = "$current_city, $current_state";
					}
				}
				printf "Location: [%s]\n", $current_location_stripped;
				#printf "0521 + 60 = %s\n", add_minutes_to_hhmm( "0521", 60 );
				#printf "05:21 + 60 = %s\n", add_minutes_to_hhcmm( "05:21", 60 );
			}
			next;
		}
		# Get month change
		# Not sure why old regex stopped working with diacritics
		#if ($_ =~ /<tr><th class="date"> *(.*)<br *\/ *>.*<\/th><th> *Gaur.bda (...) . K.*[kC]al (.\...) *<\/th><\/tr>/)
		if ($_ =~ /<tr><th class="date">\s*(.*)\s*<br *\/ *>.*Gaur.* (\d\d\d) +. +K.*al +(\d\.\d\d).*<\/th><\/tr>/)
		{
			$masa = $1;
			$gaurabda = $2;
			$calver = $3;
			printf "\n--- %s masa Gaurabda %s ver %s ---\n", $masa, $gaurabda, $calver;
			$month_changed = 1;
			next; 
		}
		# Examples (old and new):
		#<tr><td class='date'><b>19 Mar 2011</b><br /> Saturday</td><td><p class="tithi"><b>Purnima</b>, G, 05:54    , U.Phalguni</p>
		#<tr><td class='date'><b> 1 Nov 2011</b><br /> Tuesday</td><td class="cal"><p class="tithi"><b>Saptami</b>, G, 06:06    , U.Asadha  </p></td></tr>
		# Dec-2013 - class='date' changed to class="date" (double quotes), class omitted from td, more spaces
		#<tr><td class="date"><b>17 Dec 2013</b><br /> Tuesday</td><td><p class="tithi"><b>Pratipat</b>, K,     06:45, Mṛgaśīrśa</p>
		# 02-Jan-2022 (on two lines, dropped comma after tithi name, added tithi end before paksa K/G, added Sunrise-Set):
		# <tr><td class="date"><b> 1 Jan 2022</b><br />Saturday</td><td><p class="tithi"><b>CaturdaÅ›Ä«</b> 16:14, K, <b>Sunrise-Set</b> 07:27-17:42, <b>Jyeá¹£á¹­ha</b> 07:48</p><p class="event">   +MÅ«lÄ naká¹£atra up to *04:54</p>
		#</td></tr>
		#if ($_ =~ /<tr>\s*<td class=.date.>\s*<b>\s*(.+)\s*<\/b><br\s*\/\s*>\s*(\S*)\s*<\/td><td.*><p class="tithi"><b>(.*)<\/b>,*\s+(\S+)\s*,\s+(\d\d:\d\d)\s*,\s+(\S+)\s*<\/p>/)
		if ($_ =~ /<tr>\s*<td class=.date.>\s*<b>\s*(.+)\s*<\/b><br\s*\/\s*>\s*(\S*)\s*<\/td><td.*><p class="tithi"><b>(.*)<\/b>,*\s+(\S*)(\d\d:\d\d),\s+(\S+)\s*,\s+<b>Sunrise-Set<\/b>\s+(\d\d:\d\d)-(\d\d:\d\d)\s*,\s+(.+)\s*<\/p>/)
		{
			$date = $1;
			$dow = $2;
			$tithi = $3;
			$tithi_ef = $4; # Optional end flag may be *
			$tithi_et = $5; # end time hh:mm
			$paksa = $6;
			$sunrise = $7;
			$sunset = $8;
			$naksatra = $9;
			printf "Parsed date %s dow %s tithi %s %s sr %s ss %s\n", $date, $dow, $tithi, $paksa, $sunrise, $sunset;
			if ($tithi_open)
			{
			  if ($day_event_idx)
			  {
				$vevent .= "\n";
				$vtext .= "\n";
			  }
			  if ($day_event_idx >= $min_events && $tithi_visible)
			  {
				printf OUTPUT "BEGIN:VEVENT\n";
				printf OUTPUT "UID:%s\n", $vevent_uid;
				printf OUTPUT "SUMMARY:%s%s\n", $has_fast ? "*** " : "", $vevent_summary;
				printf OUTPUT "DTSTART:%s\n", $vevent_dtstart;
				printf OUTPUT "DTEND:%s\n", $vevent_dtend;
				printf OUTPUT "%sEND:VEVENT\n", $vevent;
				if ($tithi_shows_month_change)
				{
					$month_changed = 0;
				}
				$tithi_open = 0;
			  }
			  printf "%s%s\n", $has_fast ? "*** " : "", $vtext_summary;
			  if ($day_event_idx > 0)
			  {
				printf( "%s", $vtext );
			  }
			}
			$vevent = sprintf( "LOCATION:%s\n", $current_location_stripped );
			$vtext = "";
			$uid++;
			$tithi_open = 1;
			my $y;
			my $m;
			my $d;
			my $h;
			my $min;
			my $sec;
			my $zone;
			($sec, $min, $h, $d, $m, $y, $zone) = strptime( "$date $sunrise" );
			# Adjust any hh:60 time
			if ($min >= 60)
			{
				$min -= 60;
				$h++;
			}
			# Get minute offset from GMT for this sunrise
			$gmtoff = timedate_to_gmtoffset_minutes( $y + 1900, $m + 1, $d, $h, $min );
			$vtext_summary = "";
			$is_dst = ($gmtoff != $ltzm);
			if ($is_dst != $was_dst || $was_dst == -1)
			{
				$was_dst = $is_dst;
				$vtext_summary = ($is_dst ? "[DST] " : "[no dst] " );
			}
			my $sunrise_hhmm = sprintf( "%02d%02d", $h, $min );
			if ($is_dst)
			{
				$sunrise = add_minutes_to_hhcmm( $sunrise, $gmtoff - $ltzm );
				$sunrise_hhmm = add_minutes_to_hhmm( $sunrise_hhmm, $gmtoff - $ltzm );
				$sunrise_hhmm =~ /(\d\d)(\d\d)/;
				$h = $1;
				$min = $2;
			}
			$tithi_dstart = sprintf("%04d%02d%02d", $y + 1900, $m + 1, $d );
			$vevent_uid = sprintf( "vcal-%d-%08x-%s\@ayurvedayogatraining.com", $zip_hash, $entry_hash, $tithi_dstart );
			if ($tithi_dstart >= $min_date && $tithi_dstart <= $max_date)
			{
				$tithi_visible = 1;
			}
			else
			{
				$tithi_visible = 0;
			}
			$vevent_summary = sprintf( "%s %s", $paksa, $tithi );
			if ($month_changed)
			{
				$vevent_summary .= sprintf( "; %s masa, Gaurabda %s", $masa, $gaurabda );
				$tithi_shows_month_change = 1;
			}
			$vevent_dtstart = sprintf( "%sT%s00", $tithi_dstart, $sunrise_hhmm );
			#$vevent .= "DURATION:P1D\n";
			$vevent_dtend = sprintf( "%sT235959", $tithi_dstart );
			$vtext_summary .= sprintf( "%s, %s %s [%s] %s %s", $dow, $date, $paksa, $tithi, $sunrise, $naksatra );
			$day_event_idx = 0;
			$has_fast = 0;
			next;
		}
		# Get events
		if ($_ =~ /<p class="event"> *(.*) *<\/p>/)
		{
			my $event_text = $1;
			# Find and correct times for dst
			#printf "\t%s\n", $event_text;
			if ($tithi_open)
			{
				my $dst_adjusted = 0;
				if ($event_text =~ /[Ff][Aa][Ss][Tt][Ii][Nn][Gg]/)
				{
					$has_fast++;
				}
				if ($event_text =~ /[Ff][Aa][Ss][Tt]\s+[Ff][Oo][Rr]/)
				{
					$has_fast++;
				}
				if ($event_text =~ /[Ff][Aa][Ss][Tt]\s+[Tt][Ii][Ll][Ll]\s+/)
				{
					$has_fast++;
				}
				if ($event_text =~ /[Ff][Aa][Ss][Tt]\s+-\s+/)
				{
					$has_fast++;
				}
				if ($event_text =~ /Break fast (\d\d):(\d\d) - (\d\d):(\d\d)/)
				{
					my $hhmm_start = "$1$2";
					my $hhmm_end = "$3$4";
					my $hhcmm_start = "$1:$2";
					my $hhcmm_end = "$3:$4";
					my $dhhmm_start = add_minutes_to_hhmm( $hhmm_start, $gmtoff - $ltzm );
					my $dhhmm_end = add_minutes_to_hhmm( $hhmm_end, $gmtoff - $ltzm );
					$vevent_dtstart = sprintf( "%sT%s00", $tithi_dstart, $dhhmm_start );
					$vevent_dtend = sprintf( "%sT%s00", $tithi_dstart, $dhhmm_end );
					my $dhhcmm_start = add_minutes_to_hhcmm( $hhcmm_start, $gmtoff - $ltzm );
					my $dhhcmm_end = add_minutes_to_hhcmm( $hhcmm_end, $gmtoff - $ltzm );
					$event_text =~ s/$hhcmm_start/$dhhcmm_start/g;
					$event_text =~ s/$hhcmm_end/$dhhcmm_end/g;
					$dst_adjusted = 1;
				}
				# Sanitize and remove tags
				$event_text =~ s/\s*<\s*br\s*\/\s*>\s*/\\n/g;
				$event_text =~ s/<u>//g;
				$event_text =~ s/<\/u>//g;
				$event_text =~ s/<a href=".*">//g;
				$event_text =~ s/<\/a>//g;
				# Remove "Daylight savings not considered"
				if ($dst_adjusted)
				{
					if ($gmtoff != $ltzm)
					{
						$event_text =~ s/Daylight savings not considered/DST/g;
					}
					else
					{
						$event_text =~ s/Daylight savings not considered/no dst/g;
					}
				}
				if ($day_event_idx == 0)
				{
					$vevent .= sprintf( "DESCRIPTION:%s", $event_text );
				}
				else
				{
					$vevent .= sprintf( "\\n%s", $event_text );
				}
				if ($day_event_idx > 0)
				{
					$vtext .= "\n    ";
				}
				else
				{
					$vtext .= "    ";
				}
				$vtext .= $event_text;
				$day_event_idx++;
			}
			next;
		}
	}

	if ($tithi_open)
	{
	  if ($day_event_idx)
	  {
		$vevent .= "\n";
		$vtext .= "\n";
	  }
	  if ($day_event_idx >= $min_events && $tithi_visible)
	  {
		printf OUTPUT "BEGIN:VEVENT\n";
		printf OUTPUT "UID:%s\n", $vevent_uid;
		printf OUTPUT "SUMMARY:%s%s\n", $has_fast ? "*** " : "", $vevent_summary;
		printf OUTPUT "DTSTART:%s\n", $vevent_dtstart;
		printf OUTPUT "DTEND:%s\n", $vevent_dtend;
		printf OUTPUT "%sEND:VEVENT\n", $vevent;
		if ($tithi_shows_month_change)
		{
			$month_changed = 0;
		}
		$tithi_open = 0;
	  }
	  printf "%s%s\n", $has_fast ? "*** " : "", $vtext_summary;
	}

	printf OUTPUT "END:VCALENDAR\n";

	close( INPUT );
	close( OUTPUT );
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
	if ($opt =~ /--ziphash=(.*)/)
	{
		$zip_hash = $1;
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

