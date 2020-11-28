#!/bin/bash

infile=data/laposte_ouvertur.csv
if [ ! -f "$infile" -o -n "`find $infile -mtime 6`" ]; then
    mkdir -p data
    echo "Need to refetch the datanova data... OK?"
    read confirmation
    if [ -f $infile ]; then
        mv -f $infile $infile.bak
    fi
    # 137MB download
    wget 'https://datanova.laposte.fr/explore/dataset/laposte_ouvertur/download/?format=csv&timezone=Europe/Berlin&lang=fr&use_labels_for_header=true&csv_separator=%3B' -O $infile
fi

echo "Parsing datanova data to deduce opening_hours..."
if ! ./parse.pl $infile > data/new_opening_hours 2> data/warnings; then
    tail -n 1 data/warnings
    exit 1
fi
ready=`grep -v ERROR data/new_opening_hours | wc -l`
errors=`grep ERROR data/new_opening_hours | wc -l`
datanovacount=`cat data/new_opening_hours | wc -l`
statline="datanova: $datanovacount post offices: $ready with resolved rules, $errors with unresolved rules."
echo "$statline"
echo "$statline" > data/stats
echo "(see ../warnings)"

xmlfile=data/osm_post_offices.xml
osmfile=data/osm_post_offices.osm

if [ -n "`find $osmfile -mtime 1`" ]; then
    echo "Refetching all post offices via overpass..."
    mv -f $xmlfile $xmlfile.orig
    ./get_all_post_offices.py || exit 1
    xmllint --format $xmlfile > _xml && mv _xml $xmlfile
fi

osm_post_offices_count=`grep k=\"ref:FR:LaPoste\" data/osm_post_offices.xml | wc -l`
statline="OSM data: $osm_post_offices_count post offices with ref:FR:LaPoste"
echo "$statline"
echo "$statline" >> data/stats

echo "Processing XML to insert opening times..."
log=data/process_post_offices.log
./process_post_offices.py > $log || exit 1

echo "Reformatting..."
xmllint --format $osmfile > _xml && mv _xml $osmfile

diff $xmlfile $osmfile > $osmfile.diff

adding=`grep 'no opening_hours in OSM' $log | wc -l`
replacing=`grep ', replacing' $log | wc -l`
touched=`grep 'modified meanwhile' $log | wc -l`
agree=`grep agree $log | wc -l`
disagree=`grep OSM\ says $log | wc -l`
notin=`grep 'Not in datanova' $log | wc -l`
notready=`grep 'not ready' $log | wc -l`
missingPH=`grep 'missing PH off' $log | wc -l`
statline="$adding set because empty in OSM, $replacing to be updated, $missingPH only missing 'PH off', $disagree disagreements (skipped), $agree agreements, $touched skipped because modified by a human, $notin not in datanova (wrong ref?), $notready not ready (unresolved rules)"
echo "$statline"
echo "$statline" >> data/stats

actions=`grep -w modify $osmfile | wc -l`
echo "$actions objects modified in total"
echo "$actions objects modified in total" >> data/stats

mkdir -p changes
./filter_changes.py

echo "Check data/selection.osc and run ./upload_selection.sh"
