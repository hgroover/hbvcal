#!/bin/sh
# Find closest zip
# Get digital form
LONG=$1
LAT=$2
[ "${LAT}" ] || { echo "Syntax: $0 long lat where long and lat are in the form 124W05 40N52 OR -124.123 40.8233"; exit 1; }
[ -r zips/zip_codes.sql ] || { echo "Need zips/zip_codes.sql"; exit 1; }
eval $(echo ${LONG} | gawk '/[0-9]{2,3}[NSEW][0-9]{2}/ {print "ISDIG=0"; next;} {print "ISDIG=1";}')
if [ ${ISDIG} = 1 ]
then
  LONG_DIG=${LONG}
  LAT_DIG=${LAT}
  echo "Detected ${LONG} ${LAT} as already digital form"
  eval $(echo "${LONG}" | gawk '{longs="E"; long=$1; if (long < 0) {long=-long; longs="W";}; longd=int(long); longf=long-longd; printf( "LONGN=%03d%s%07.4f", longd, longs, longf * 60 );}')
  eval $(echo "${LAT}" | gawk '{lats="N"; lat=$1; if (lat<0) {lat=-lat; lats="S";}; longd=int(long); latd=int(lat); longf=long-longd; latf=lat-latd; printf( "LATN=%02d%s%07.4f", latd, lats, latf * 60 );}')
  echo "Normal form: ${LONGN} ${LATN}"
else
eval $(echo ${LONG} | gawk '{match($0,/(.+)([EW])(.+)/,a); printf("LONG_D=%d; LONG_SGN=%s; LONG_M=%d\n", a[1], a[2], a[3]);}')
#echo "LONG_D=${LONG_D}; LONG_SGN=${LONG_SGN}; LONG_M=${LONG_M}"
eval $(echo ${LAT} | gawk '{match($0,/(.+)([NS])(.+)/,a); printf("LAT_D=%d; LAT_SGN=%s; LAT_M=%d\n", a[1], a[2], a[3]);}')
#echo "LAT_D=${LAT_D}; LAT_SGN=${LAT_SGN}; LAT_M=${LAT_M}"
if [ ${LONG_SGN} = W ]
then
  LONG_DSGN=-1
else
  LONG_DSGN=1
fi
if [ ${LAT_SGN} = S ]
then
  LAT_DSGN=-1
else
  LAT_DSGN=1
fi
LONG_DIG="$(perl -e "printf \"%10.5f\n\", ${LONG_DSGN} * (${LONG_D} + ${LONG_M} / 60.0)")"
LAT_DIG="$(perl -e "printf \"%10.6f\n\", ${LAT_DSGN} * (${LAT_D} + ${LAT_M} / 60.0)")"
echo "LONG_DIG=${LONG_DIG} LAT_DIG=${LAT_DIG}"
fi
# Row example:
#INSERT INTO `zip_codes` VALUES ('47922', 'IN', ' 40.868500', ' -87.35899', 'Brook', 'Indiana');
#INSERT INTO `zip_codes` VALUES ('99557', 'AK', ' 61.570981', '-158.88072', 'Chuathbaluk', 'Alaska');
# Build regex that uses only first two places
LONG_TRUNC="$(echo "${LONG_DIG}" | awk -F'\t' '{print substr($0,1,7);}')"
LAT_TRUNC="$(echo "${LAT_DIG}" | awk -F'\t' '{print substr($0,1,6);}')"
REGEX="' *${LAT_TRUNC}.+', ' *${LONG_TRUNC}.+',"
echo "REGEX=${REGEX} from ${LONG_DIG} ${LAT_DIG}"
if egrep "${REGEX}" zips/zip_codes.sql
then
  echo "Found"
else
LONG_TRUNC="$(echo "${LONG_DIG}" | awk -F'\t' '{print substr($0,1,6);}')"
LAT_TRUNC="$(echo "${LAT_DIG}" | awk -F'\t' '{print substr($0,1,5);}')"
REGEX="' *${LAT_TRUNC}.+', ' *${LONG_TRUNC}.+',"
echo "REGEX=${REGEX}"
egrep "${REGEX}" zips/zip_codes.sql
fi


