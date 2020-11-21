# DataNovaImportScripts
Import scripts for datanova.laposte.fr into OSM

See https://wiki.openstreetmap.org/wiki/Import/FrenchPostOfficeOpeningHours

# Implemented features

## datanova data parser (parse.pl):
* Day-of-week grouping as shown in the Data Preparation example
* Detect Different opening times in different years. Example: `Fr 09:00-12:30; 2020 Fr 09:15-11:45`
* Detect Nth saturday of the month (e.g. `Sa[1]`), last saturday of each month, (`Sa[-1]`). Not just for saturdays, but that's where it happens most :)
* Detect one-whole-month rule, example `Sa 08:00-12:00; 2021 Jan Sa 09:00-12:00` (because it's 08:00-12:00 again in February)
* Ignore changes that will only take effect at a future date. opening\_hours doesn't support that, we'll just have to rely on a future import writing out the new opening hours.
* Detect "Every other Saturday", example: `week 01-53/2 Sa 09:00-12:00` (implicitly off the other week). In 2021 this swaps around (because w1 follows w53), but we can update that later, same reasoning as the previous point.
* Automated regression tests for the parser

## OSM modification script (process\_post\_offices.py):
For each OSM post office with "ref:FR:LaPoste=*" attribute, detect and handle these cases:
* Post office not in the datanova data (skip)
* No opening hours to set because the datanova data parser failed to create a recurring rule (skip)
* No hours in OSM -- this is the common case until the first import (set them)
* Agreement on the opening_hours (skip)
* Agreement on the opening_hours except for a missing 'PH off' in OSM (add it)
* Hours in datanova have changed, and nobody modified the hours previously set by the script (replace them)
* Hours in datanova have changed, but someone changed the hours in OSM (skip)
* OSM and datanova simply have different data (skip)

# Setup

## Older lark due to https://github.com/rezemika/humanized\_opening\_hours/issues/34
git clone https://github.com/lark-parser/lark.git
cd lark ; git checkout 0.6.6
python3 ./setup.py install --prefix /home/dfaure/.local

## osm-bulk-upload (do this in the parent directory)
git clone https://github.com/grigory-rechistov/osm-bulk-upload

## Other dependencies
pip install overpass
pip install oh\_sanitizer
