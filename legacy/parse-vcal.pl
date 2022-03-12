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

# Current gmt offset in minutes - set by is_date_dst
my $gmtoff = 0;

# gmt offset for current date
my $ltzm = 0;

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
	my $nakend_f = "";
	my $nakend = "";
	my $harikatha = "";
	my $fulltext = "";
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
	# Globalized
	#my $gmtoff = 0;
	#my $ltzm = 0;
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
		# Initially we'll get a masa without the gaurabda
		# Examples (old and new):
		#<tr><td class='date'><b>19 Mar 2011</b><br /> Saturday</td><td><p class="tithi"><b>Purnima</b>, G, 05:54    , U.Phalguni</p>
		#<tr><td class='date'><b> 1 Nov 2011</b><br /> Tuesday</td><td class="cal"><p class="tithi"><b>Saptami</b>, G, 06:06    , U.Asadha  </p></td></tr>
		# Dec-2013 - class='date' changed to class="date" (double quotes), class omitted from td, more spaces
		#<tr><td class="date"><b>17 Dec 2013</b><br /> Tuesday</td><td><p class="tithi"><b>Pratipat</b>, K,     06:45, Mṛgaśīrśa</p>
		# 02-Jan-2022 (on two lines, dropped comma after tithi name, added tithi end before paksa K/G, added Sunrise-Set):
		# <tr><td class="date"><b> 1 Jan 2022</b><br />Saturday</td><td><p class="tithi"><b>CaturdaÅ›Ä«</b> 16:14, K, <b>Sunrise-Set</b> 07:27-17:42, <b>Jyeá¹£á¹­ha</b> 07:48</p><p class="event">   +MÅ«lÄ naká¹£atra up to *04:54</p>
		#<tr><td class="date"><b> 2 Jan 2022</b><br />Sunday</td><td><p class="tithi"><b>Amāvasyā</b> 12:35, K, <b>Sunrise-Set</b> 07:28-17:42, <b>Purvāṣāḍhā</b> *02:04</p></td></tr>
		# <tr><td class="date"><b> 6 Jan 2022</b><br />Thursday</td><td><p class="tithi"><b>Pañcamī</b> 23:43, G, <b>Sunrise-Set</b> 07:28-17:45, <b>Śatabhiṣā</b> 18:51, <a href="https://www.purebhakti.com/component/tags/tag/291" target="_blank"><u>Tithi hari-kathā</u></a></p></td></tr>
		# <tr><td class="date"><b>12 Jan 2022</b><br />Wednesday</td><td><p class="tithi"><b>Ekādaśī</b> --:--, G, <b>Sunrise-Set</b> 07:28-17:50, <b>Kṛttikā</b> *05:38, <a href="https://www.purebhakti.com/component/tags/tag/297" target="_blank"><u>Tithi hari-kathā</u></a></p><p class="event">   +(not suitable for fasting, see following day)</p>
		# (following line has </td></tr> only)
		# ------------------------[$1       ]----------[$2    ]----------------------------[$3        ]----[[$5 ]
		#                          |                    |
		#                          +----------------+   +----------------------+
		#                                           |                          |  
		# We may have , tithi hari-katha before the </p> and we may have an additional <p>text</p> after that,
		# and the close </td></tr> may come on the next line (if we have the additional text). Tithis that don't
		# end before sunrise will have __:__ and the same applies for naksatras. We won't handle locations north
		# of the arctic circle or south of the antarctic circle.
		if ($_ =~ /<tr>\s*<td class=.date.>\s*<b>\s*(.+)\s*<\/b><br\s*\/\s*>\s*(\S*)\s*<\/td><td.*><p class="tithi"><b>(.*)<\/b>\s+(\S?)(..:..),\s+(\S+)\s*,\s+<b>Sunrise-Set<\/b>\s+(\d\d:\d\d)-(\d\d:\d\d)\s*,\s+<b>(.+)\s*<\/b>\s+(\S?)(..:..)(,\s+(.+))*\s*<\/p>(<p class="event">\s*(.*)\s*<\/p>)*/)
		{
			if ($tithi_open)
			{
				# Close previous tithi
				printf OUTPUT "SUMMARY:%s%s\n", $has_fast ? "*** " : "", $vevent_summary;
				printf OUTPUT "DESCRIPTION:%s\n", $vtext;
				printf OUTPUT "END:VEVENT\n";
				$tithi_open = 0;
				$has_fast = 0;
			}
			$date = $1;
			$dow = $2;
			$tithi = $3;
			$tithi_ef = $4; # Optional end flag may be *
			$tithi_et = $5; # end time hh:mm
			$paksa = $6;
			$sunrise = $7;
			$sunset = $8;
			$naksatra = $9;
			$nakend_f = $10;
			$nakend = $11;
			$harikatha = $13;
			$fulltext = $15;
			$is_dst = is_date_dst( "$date $sunrise" );
			$vtext = "";
			$vevent_summary = "";
			if ($is_dst != $was_dst || $was_dst == -1)
			{
				$was_dst = $is_dst;
				$vtext = ($is_dst ? "[DST] " : "[no dst] " );
			}

			printf "Parsed date %s dow %s dst %d tithi %s [%s%s] %s sr %s ss %s nak %s %s %s hk [%s] ft [%s]\n", $date, $dow, $is_dst, $tithi, $tithi_ef, $tithi_et, $paksa, $sunrise, $sunset, $naksatra, $nakend, $nakend_f, $harikatha, $fulltext;
			# With the new format we COULD have everything on a single line thus no need for any stateful processing.
			# Although we've extracted $fulltext here we're going to parse and process it separately.
			$tithi_open = 1;
			$uid++;
			
			# Adjust sunrise, sunset, tithi_et (if defined), nakend
			my ($sec, $min, $h, $d, $m, $y, $zone) = strptime( "$date $sunrise" );
			# Adjust any hh:60 time
			if ($min >= 60)
			{
				$min -= 60;
				$h++;
			}
			$tithi_dstart = sprintf("%04d%02d%02d", $y + 1900, $m + 1, $d );
			$vevent_uid = sprintf( "vcal-%d-%08x-%s\@naya-ayurveda.com", $zip_hash, $entry_hash, $tithi_dstart );
			if ($tithi_dstart >= $min_date && $tithi_dstart <= $max_date)
			{
				$tithi_visible = 1;
			}
			else
			{
				$tithi_visible = 0;
			}
			my $sunrise_hhmm = sprintf( "%02d%02d", $h, $min );
			if ($is_dst)
			{
				$sunrise = add_minutes_to_hhcmm( $sunrise, $gmtoff - $ltzm );
				$sunrise_hhmm = add_minutes_to_hhmm( $sunrise_hhmm, $gmtoff - $ltzm );
			}
			$vevent_dtstart = sprintf( "%sT%s00", $tithi_dstart, $sunrise_hhmm );
			($sec, $min, $h, $d, $m, $y, $zone) = strptime( "$date $sunset" );
			my $sunset_hhmm = sprintf( "%02d%02d", $h, $min );
			if ($is_dst)
			{
				$sunset = add_minutes_to_hhcmm( $sunset, $gmtoff - $ltzm );
				$sunset_hhmm = add_minutes_to_hhmm( $sunset_hhmm, $gmtoff - $ltzm );
			}
			$vevent_dtend = sprintf( "%sT%s00", $tithi_dstart, $sunset_hhmm );
			# This is going to be inaccurate when naksatra / tithi ends the next day!
			($sec, $min, $h, $d, $m, $y, $zone) = strptime( "$date $nakend" );
			if ($is_dst)
			{
				$nakend = add_minutes_to_hhcmm( $nakend, $gmtoff - $ltzm );
			}
			($sec, $min, $h, $d, $m, $y, $zone) = strptime( "$date $tithi_et" );
			if ($is_dst)
			{
				$tithi_et = add_minutes_to_hhcmm( $tithi_et, $gmtoff - $ltzm );
			}
			$vevent_summary = sprintf( "%s %s", $paksa, $tithi );
			if ($month_changed)
			{
				$vevent_summary .= sprintf( "; %s masa, Gaurabda %s", $masa, $gaurabda );
				$month_changed = 0;
			}
			# If changed between DST / no dst, prefixed with [DST] or [no dst]
			# Then Sunday, 13 Mar 2022 G Ekadasi sunrise 07:45 sunset 18:23 tithi ends *02:21 Punarvasu naksatra
			# Either tithi or naksatra may not have an end, may be same day or *next day
			$vtext .= sprintf( "%s, %s %s %s sunrise %s sunset %s", $dow, $date, $paksa, $tithi, $sunrise, $sunset );
			if ($tithi_et ne "--:--")
			{
				$vtext .= sprintf( " tithi ends %s%s", $tithi_ef, $tithi_et );
			}
			$vtext .= sprintf( " %s naksatra", $naksatra );
			if ($nakend ne "--:--")
			{
				$vtext .= sprintf( " ends %s%s", $nakend_f, $nakend );
			}
			
			# Create event entry - start at sunrise, end at sunset, prepend adjusted tithi end / naksatra end to full text
			printf OUTPUT "BEGIN:VEVENT\n";
			printf OUTPUT "UID:%s\n", $vevent_uid;
			printf OUTPUT "DTSTART:%s\n", $vevent_dtstart;
			printf OUTPUT "DTEND:%s\n", $vevent_dtend;
			printf OUTPUT "LOCATION:%s\n", $current_location_stripped;
			# We do get multiple lines which will be additional <p class="event">...</p>
			# We may also have an event clause on the same line
		}
		
		# Get event lines separate from tithi
		if ($_ =~ /<p class="event"> *(.*) *<\/p>/)
		{
			my $event_text = $1;
			# Find and correct times for dst
			#printf "\t%s\n", $event_text;
			if ($tithi_open)
			{
				my $dst_adjusted = 0;
				# We should always have "fasting for" and should ignore "not suitable for fasting"
				if ($event_text =~ /[Ff][Aa][Ss][Tt][Ii][Nn][Gg]\s+[Ff][Oo][Rr]/)
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
				# We may have
				# +Trayodaśī up to *06:01, Tithi hari-kathā
				if ($event_text =~ /\s*(.*)\s*(\S+.* up to ?)(\d\d):(\d\d)(.*)/)
				{
					my $prefix = $1;
					my $subject = $2;
					my $hhmm = "$3$4";
					my $suffix = $5;
					my $hhcmm = "$3:$4";
					my $dhhmm = add_minutes_to_hhmm( $hhmm, $gmtoff - $ltzm );
					my $dhhcmm = add_minutes_to_hhcmm( $hhcmm, $gmtoff - $ltzm );
					$event_text =~ s/$hhcmm/$dhhcmm/g;
					$dst_adjusted = 1;
				}
				# +Break fast 07:23 - 09:10 (Daylight-saving time not considered. If in effect, please adjust time. See Calendar Information.)
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
				# Replace <someone> ~ Appearance with A: <someone>
				$event_text =~ s/\+(.+) ~ Appearance/A: \1/g;
				$event_text =~ s/\+(.+) ~ Disappearance/D: \1/g;
				# Remove "Daylight savings not considered"
				# Later variant "Daylight-saving time not considered"
				if ($dst_adjusted)
				{
					if ($gmtoff != $ltzm)
					{
						$event_text =~ s/(Daylight savings|Daylight-saving time) not considered(. If in effect, please adjust time. See Calendar Information.)*/DST/g;
					}
					else
					{
						$event_text =~ s/(Daylight savings|Daylight-saving time) not considered(. If in effect, please adjust time. See Calendar Information.)*/no dst/g;
					}
				}
				$vtext .= sprintf( "\\n%s", $event_text );
				$day_event_idx++;
			}
			next;
		}
	}

	# If we ended with an open tithi, close it
	if ($tithi_open)
	{
		# Close remaining tithi
		printf OUTPUT "SUMMARY:%s%s\n", $has_fast ? "*** " : "", $vevent_summary;
		printf OUTPUT "DESCRIPTION:%s\n", $vtext;
		printf OUTPUT "END:VEVENT\n";
		$tithi_open = 0;
		$has_fast = 0;
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

# Given a date/time (e.g. "${date} ${sunrise}" return 1 if dst, 0 if not
sub is_date_dst()
{
	my ($dt) = @_;
			my $y;
			my $m;
			my $d;
			my $h;
			my $min;
			my $sec;
			my $zone;
	my ($sec, $min, $h, $d, $m, $y, $zone) = strptime( $dt );
	# Adjust any hh:60 time
	if ($min >= 60)
	{
		$min -= 60;
		$h++;
	}
	# Get minute offset from GMT for this sunrise ($gmtoff and $ltzm are global)
	$gmtoff = timedate_to_gmtoffset_minutes( $y + 1900, $m + 1, $d, $h, $min );
	if ($gmtoff != $ltzm)
	{
		return 1;
	}
	return 0;
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

