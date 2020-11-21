#!/bin/sh
password=`pass show osmbot-openstreetmap.org | head -n 1`
date=`date +%Y-%m-%d`
version=`cat ./version`

changeset=data/selection.osc

../osm-bulk-upload/upload.py -u davidfaure_bot -p $password -c yes -m 'Set opening hours, see https://wiki.openstreetmap.org/wiki/Import/FrenchPostOfficeOpeningHours' $changeset -x "DataNovaImportScripts $version" -y "datanova.laposte.fr, $date"
exitcode=$?

# I only modify, no creation, so I don't need the id mapping
rm -f data/selection.diff.xml

if [ $? -eq 0 ]; then
    # Success
    ./commit_changes_locally.py
fi
