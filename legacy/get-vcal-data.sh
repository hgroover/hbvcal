#!/bin/sh
# Get vaishnava calendar for specified timezone code and location string
URL=http://www.purebhakti.com/resources/vaisnava-calendar-mainmenu-71.html
# Some time in 2018-2019, this changed (based on the 302 / 301 responses)
# Switched to https in 2020
URL=https://www.purebhakti.com/resources/vaisnava-calendar
OUTPUT="$1"
TIMEZONE="$2"
LOCATION="$3"
[ "${LOCATION}" ] || { echo "Syntax: $0 output-file timecode \"location\""; exit 1; }

[ -e "${OUTPUT}" ] && { echo "Output file ${OUTPUT} exists - removing..."; sleep 4; rm -f "${OUTPUT}"; }

#LOCATION="San Diego, California, USA    117W05 32N45     -8.00"
#LOCATION="Escondido, CA USA             117W06 33N10     -8.00"
#LOCATION="Oxnard, CA USA                119W10 34N12     -8.00"
TMPBASE=/tmp/get-vcal-data-$$
REFERRER=http://www.google.com
USER_AGENT="Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.6) Gecko/20070725 Firefox/2.0.0.6"
ACCEPT="Accept:text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5"
ACCEPT_LANGUAGE="Accept-Language: en-us,en;q=0.5"
ACCEPT_ENCODING="Accept-Encoding: gzip,deflate"
ACCEPT_CHARSET="Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7"
KEEP_ALIVE="Keep-Alive: 300"
wget -O ${TMPBASE}.p1 \
	--cookies=on --keep-session-cookies --save-cookies=${TMPBASE}.cookies \
	--referer="${REFERRER}" --user-agent="${USER_AGENT}" \
	--header="${ACCEPT}" --header="${ACCEPT_LANGUAGE}" --header="${ACCEPT_ENCODING}" \
	--header="${ACCEPT_CHARSET}" --header="${KEEP_ALIVE}" \
	${URL} || { echo "Failed to establish session - output in ${TMPBASE}.*"; exit 1; }
[ ${TIMEZONE} = list ] && {
  echo "Copying timezone code list to ${OUTPUT}"
  mv ${TMPBASE}.p1 "${OUTPUT}"
  exit 0
}

REFERRER=${URL}
echo "Waiting a few seconds to seem human..."
sleep 5
wget -O ${TMPBASE}.p2 \
	--cookies=on --keep-session-cookies --load-cookies=${TMPBASE}.cookies --save-cookies=${TMPBASE}.cookies \
	--referer="${REFERRER}" --user-agent="${USER_AGENT}" \
	--header="${ACCEPT}" --header="${ACCEPT_LANGUAGE}" --header="${ACCEPT_ENCODING}" \
	--header="${ACCEPT_CHARSET}" --header="${KEEP_ALIVE}" \
	--post-data "action=1&timezone=${TIMEZONE}&button=Submit Time Zone" \
	${URL} || { echo "Failed to get second page - output in ${TMPBASE}.*"; exit 1; }
[ "${LOCATION}" = "place-list" ] && {
  echo "Copying place list for timezone code ${TIMEZON} to ${OUTPUT}"
  mv ${TMPBASE}.p2 "${OUTPUT}"
  rm ${TMPBASE}.*
  exit 0
}

echo "Waiting a few more seconds to seem less robotic..."
sleep 7
if wget -O "${OUTPUT}" \
	--cookies=on --keep-session-cookies --load-cookies=${TMPBASE}.cookies --save-cookies=${TMPBASE}.cookies \
	--referer="${REFERRER}" --user-agent="${USER_AGENT}" \
	--header="${ACCEPT}" --header="${ACCEPT_LANGUAGE}" --header="${ACCEPT_ENCODING}" \
	--header="${ACCEPT_CHARSET}" --header="${KEEP_ALIVE}" \
	--post-data "action=2&timezone=${TIMEZONE}&location=${LOCATION}&button=Get Calendar" \
	${URL}
then
  echo "-- Successfully downloaded --"
  # Comment this out only for debugging
  rm -f ${TMPBASE}.*
  #echo "-- did NOT delete ${TMPBASE}.* - to clean up, run"
  #echo "rm -f ${TMPBASE}.*"
else
  echo "-- download failed - partial results in ${TMPBASE} and in ${OUTPUT} --"
fi


