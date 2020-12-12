#!/bin/sh
password=`pass show osmbot-openstreetmap.org | head -n 1`
date=`date +%Y-%m-%d`
version=`cat ./version`

for changeset in changes/*.osc; do

    comment="Import des opening_hours sur les bureaux de poste n'en ayant pas"
    case $changeset in
        */ph_off_*)
            comment="Import des opening_hours: PH off manquant"
            ;;
        */update_*)
            comment="Mise à jour des opening_hours précédemment importés"
            ;;
    esac

    url="https://wiki.openstreetmap.org/wiki/Import/FrenchPostOfficeOpeningHours"

    # Note that these two tags were hacked directly into upload.py:
    # import=yes
    ../osm-bulk-upload/upload.py -u davidfaure_bot -p $password -c yes -m "$comment" $changeset \
    -x "DataNovaImportScripts $version, via osm-bulk-upload/python.py" -y "datanova.laposte.fr, $date" -z "$url"
    exitcode=$?

    if [ $exitcode -eq 0 ]; then
        # Success
        hoursfile=`echo $changeset | sed -e 's/osc/hours/'`
        ./commit_changes_locally.py $hoursfile
    fi
done
