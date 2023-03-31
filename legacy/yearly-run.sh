#!/bin/sh
# yearly run

LIST="US-92105 US-94102 US-90023 US-78721 US-33125 US-33607 US-32615 US-32801 IN-741302 IN-281121 IN-110058 UK-SW1A1AA "
LIST="${LIST} UK-B82QE UK-BS16QF UK-CF142QQ IE-9MX6G8 NL-1094CC RS-11060 DE-13351 ES-19400 
DE-80636 IT-80139 FR-75014 IT-00195 SE-11451 AT-1090 PL-00227 CH-6319 "

echo "Processing ${LIST}"
for zip in ${LIST}
do
  if ./get-vcal2.pl --zip=${zip}
  then
	echo "=============
	Success ${zip}
==============
"
  else
	echo "=============
    FAILED ${zip}
==============
"
  fi
done

echo "Completed"
