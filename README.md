# DataNovaImportScripts
Import scripts for datanova.laposte.fr into OSM

See https://wiki.openstreetmap.org/wiki/Import/FrenchPostOfficeOpeningHours

# Setup

## Older lark due to https://github.com/rezemika/humanized\_opening\_hours/issues/34
git clone https://github.com/lark-parser/lark.git
cd lark ; git checkout 0.6.6
python3 ./setup.py install --prefix /home/dfaure/.local

## Other dependencies
pip install overpass
pip install oh\_sanitizer
