#!/bin/bash

echo "Running regression tests..."
regression_tests/run_all.sh > /dev/null || exit 1

if [ -n "$KEEPOLD" ]; then
    echo "ERROR: KEEPOLD=1 is for the unittests, don't run the real script with it"
    exit 1
fi

if [ "$1" = "-updateosm" ]; then
    updateosm=1
fi

infile=data/laposte_ouvertur.csv
if [ ! -s "$infile" -o -n "`find $infile -mtime +4  2>/dev/null`" ]; then
    mkdir -p data
    echo "Need to refetch the datanova data... OK?"
    read confirmation
    if [ -f $infile ]; then
        mv -f $infile $infile.bak
    fi
    # 137MB download
    wget 'https://datanova.laposte.fr/explore/dataset/laposte_ouvertur/download/?format=csv&timezone=Europe/Berlin&lang=fr&use_labels_for_header=true&csv_separator=%3B' -O $infile
fi

date=`date +'%Y-%m-%d'`

if [ -f data/new_opening_hours ]; then
    mv data/new_opening_hours data/new_opening_hours.bak
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
stats=data/stats_$date
if [ -f $stats ]; then
    cp -f $stats ${stats}.bak
fi
statslink=data/stats
rm -f $statslink
ln -s ../$stats $statslink
echo "$statline"
echo "$statline" > $stats
echo "(see ../warnings)"

xmlfile=data/osm_post_offices.xml
osmfile=data/osm_post_offices.osm

if [ -n "$updateosm" -o ! -f $xmlfile -o -n "`find $xmlfile -mtime +1 2>/dev/null`" ]; then
    echo "Refetching all post offices via overpass..."
    if [ -f $xmlfile ]; then
        mv -f $xmlfile $xmlfile.bak
    fi
    ./get_all_post_offices.py || exit 1
    xmllint --format $xmlfile > _xml && mv _xml $xmlfile
fi

osm_post_offices_count=`grep k=\"ref:FR:LaPoste\" data/osm_post_offices.xml | wc -l`
statline="OSM data: $osm_post_offices_count post offices with ref:FR:LaPoste"
echo "$statline"
echo "$statline" >> $stats

echo "Processing XML to insert opening times..."
log=data/process_post_offices_$date.log
loglink=data/process_post_offices.log
if [ -f $log ]; then
    mv $log $log.bak
fi
rm -f $loglink
./process_post_offices.py > $log || exit 1
ln -s ../$log $loglink

echo "Reformatting..."
xmllint --format $osmfile > _xml && mv _xml $osmfile

diff $xmlfile $osmfile > $osmfile.diff

adding=`grep 'no opening_hours in OSM' $log | wc -l`
replacing=`grep ', replacing' $log | wc -l`
touched=`grep 'modified meanwhile' $log | wc -l`
agree=`grep agree $log | wc -l`
disagree=`grep OSM\ says $log | wc -l`
notin=`grep 'Not in datanova' $log | wc -l`
onlycovid=`grep 'no opening_hours but covid hours' $log | wc -l`
notready=`grep 'not ready' $log | wc -l`
missingPH=`grep 'missing PH off' $log | wc -l`
duperef=`grep 'duplicate ref' $log | wc -l`
statline="$adding set because empty in OSM, $replacing to be updated, $missingPH only missing 'PH off', $disagree disagreements (skipped), $agree agreements, $touched skipped because modified by a human, $onlycovid blocked by covid hours (opening_hours empty), $notin not in datanova (wrong ref?), $duperef duplicate refs in OSM, $notready not ready (unresolved rules)"
echo "$statline"
echo "$statline" >> $stats

actions=`grep -w modify $osmfile | wc -l`
echo "$actions objects modified in total"
echo "$actions objects modified in total" >> $stats

./filter_changes.py

echo 'Check data/process_post_offices.log and run ./upload_all.sh'
echo 'Then remember to commit'
