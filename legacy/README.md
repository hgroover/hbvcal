Legacy Vaishnava Calendar processing

This is an old collection of Perl and bash scripts to fetch the
PureBhakti.com Vaishnava calendar and process it into ics format
(for use with Google Calendar and other calendar programs).

Operational notes are in update-process.txt

What it does

Parse HTML contents of page (which is a moving target; the formatting has
changed several times, most recently and drastically in January 2022).
Convert times into local time (using the Olsen time change designations,
e.g. America/Chicago, etc) and produce an ics calendar.

Why you might need this

If you follow the Gaudiya Vaishnava Calendar or just want to get tithi
and naksatra changes (say, to follow Ekadasi-vrata) this allows you to
pick a supported location and generate the calendar. Currently this uses
US zipcodes as a unique identifier but the parsing is the same regardless
of location. At some point we'll update this to use a better unique
identifier which is not US-specific.

If you just want a calendar on your device, you can just use one of the
shared calendars that I maintain.

