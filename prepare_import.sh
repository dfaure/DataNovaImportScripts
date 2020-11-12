# 137MB download
# wget 'https://datanova.laposte.fr/explore/dataset/laposte_ouvertur/download/?format=csv&timezone=Europe/Berlin&lang=fr&use_labels_for_header=true&csv_separator=%3B' -O data/laposte_ouvertur.csv

./parse.pl data/laposte_ouvertur.csv > data/new_opening_hours 2> data/warnings
ready=`grep -v ERROR data/new_opening_hours | wc -l`
errors=`grep ERROR data/new_opening_hours | wc -l`
echo "$ready post offices ready for import, $errors post offices with unresolved rules."
echo "(see ../warnings)"

./get_all_post_offices.py && ./process_post_offices.py

xmllint --format data/osm_post_offices.xml > _xml && mv _xml data/osm_post_offices.xml
xmllint --format data/osm_post_offices.osm > _xml && mv _xml data/osm_post_offices.osm

actions=`grep -w modify data/osm_post_offices.osm | wc -l`
echo "$actions objects modified"
