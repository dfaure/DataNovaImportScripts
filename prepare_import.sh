#!/bin/bash

infile=data/laposte_ouvertur.csv
if [ -n "`find $infile -mtime 6`" ]; then
    echo "Refetching datanova data..."
    exit 1
    if [ -f $infile ]; then
        mv -f $infile $infile.bak
    fi
    # 137MB download
    wget 'https://datanova.laposte.fr/explore/dataset/laposte_ouvertur/download/?format=csv&timezone=Europe/Berlin&lang=fr&use_labels_for_header=true&csv_separator=%3B' -O $infile
fi

echo "Parsing datanova data to deduce opening_hours..."
./parse.pl $infile > data/new_opening_hours 2> data/warnings
ready=`grep -v ERROR data/new_opening_hours | wc -l`
errors=`grep ERROR data/new_opening_hours | wc -l`
echo "$ready post offices ready for import, $errors post offices with unresolved rules."
echo "(see ../warnings)"

xmlfile=data/osm_post_offices.xml
osmfile=data/osm_post_offices.osm

if [ -n "`find $osmfile -mtime 1`" ]; then
    echo "Refetching all post offices via overpass..."
    ./get_all_post_offices.py || exit 1
fi

echo "Processing XML to insert opening times..."
./process_post_offices.py > data/process_post_offices.log || exit 1

echo "Reformatting..."
xmllint --format $xmlfile > _xml && mv _xml $xmlfile
xmllint --format $osmfile > _xml && mv _xml $osmfile

actions=`grep -w modify $osmfile | wc -l`
echo "$actions objects modified, use JOSM to import $osmfile"
