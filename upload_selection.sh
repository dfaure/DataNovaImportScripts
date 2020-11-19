#!/bin/sh
password=`pass show osmbot-openstreetmap.org | head -n 1`
date=`date +%Y-%m-%d`
version=`cat ./version`

../osm-bulk-upload/upload.py -u davidfaure_bot -p $password -c yes -m 'Set opening hours, see https://wiki.openstreetmap.org/wiki/Import/FrenchPostOfficeOpeningHours' data/selection.osc -x "DataNovaImportScripts $version" -y "datanova.laposte.fr, $date"

# I only modify, no creation, so I don't need the id mapping
rm -f data/selection.diff.xml
