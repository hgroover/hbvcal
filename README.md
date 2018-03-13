hbvcal

This project is in early alpha. All commits will be directly on master
until we accumulate enough to be actually useful, then we'll fork development
and use master for releases.

This GPL2 project includes code and references to create an open-source,
reusable core to calculate the Vaishnava calendar with tithi rules applied
according to the Sanskrit book Sri Hari-bhakti-vilasa by Sri Gopal Bhatta
Goswami. This was compiled some time in the 1600s. We are using a fairly
recent edition with the original Sanskrit in Devanagari with Hindi translation
and commentary published by Sri Haridas Shastri, Radhakund, UP, India.

Although there have been at least two other calendar projects that we know
of based on rules from Sri Hari-bhakti-vilasa, this one aims to provide
better transparency by publishing it as an open-source project with a GPL 2.0
license.

There are a few reasons for this. One is that for calculation we use the
GPL-licensed Swiss Ephemeris. Precise calculation of solar and lunar positions
is critical, as well as calculation of solar and lunar eclipses. Another
very important reason is that implementing the logic for evaluation of
rules in Sanskrit literature requires some background understanding of
jyotir-veda (astronomy), nyaya (logic) and sankhya (categorical analysis).
In short, translation of rules into computer logic may be subject to
interpretation, and will also benefit from the broader review that a public
benefit project gains from being open-source.

What exactly is this?

There are some core concepts such as tithi which are central.

Briefly: take the time between one full moon and the next, with new 
moon as the midpoint; divide each fortnight into 15 equal portions 
with respect to angle; and the beginning and end times of the angle 
portions are called tithis. Much of the interpretive part (where rules
from Sri Hari-bhakti-vilasa come in) has to do with determining what
tithi is observed on a given solar day (where a solar day is determined
by the time of sunrise in a particular geographic location).

Times are critical as they are part of observance of fasting and other
religious vows. There are rules from other sources as well, such as
Sri Narada-pancaratra. Smarta-vidhi may take yet another approach for
evaluation of rules for observance of tithi, and the Tamil calendar
may also have long-standing traditional rules. It is still common for
observance of festivals such as Dipavali, Janmastami and Sri Rama Navami
to be calculated for a place in India even for observances in other
countries.

Our hope is that we can organize the calculation of tithis into three
blocks:

Block 1 - astronomy with options
This basically is the part where we calculate solar and lunar positions.
These are observable phenomena and match Newtonian physics and older systems
of calculation. Most of the heavy lifting in this area is done in the Swiss
Ephemeris code. Interestingly, modern ephemeris routines use a heliocentric
model and iterative solution of integral calculus according to Newtonian
physics (although some very small corrections for relativistic effects on
visible light are made in one or two cases that I know of). This is all very
commonsense and relates to observation. The interesting part is that this
matches fairly closely to older methods described in Surya-siddhanta, a
text dating back to at least 800 AD. My apologies to flat earthers, if you
want to make the math used in tithi calculations match up with your theories,
you don't have even a working theory, either modern or ancient.
The preferred language here would be C++ or Java.

Block 2 - evaluation of rules
This is where we evaluate sets of rules to match up with leap month, specific
tithis and the correlation of solar days to particular tithis. There could be
different sets of rules in this section. To start with we're only implementing 
rules from Sri Hari-bhakti-vilasa, but if you wanted to produce a Tamil
calendar, smarta calendar, or other, you'd just need to contribute your own
rules.
The preferred language here would be Python.

Block 3 - presentation
This is the section dealing with the (relatively) easy stuff - conversion
to ical and other formats, dealing with time zones and time changes (i.e.
localization), presentation in different languages, etc. There would be
some very lightweight content management for things like notes, explanations,
annotations, etc.

