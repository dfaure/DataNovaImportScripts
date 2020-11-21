#!/usr/bin/env python3
import os
import subprocess
# https://docs.python.org/3/library/xml.etree.elementtree.html#module-xml.etree.ElementTree
import xml.etree.ElementTree as ET

# open the full output from process_post_offices.py
xmlfile = open("data/osm_post_offices.osm", "r")
response = xmlfile.read()

# parse office id -> office name dict, to keep .hours files readable
office_names = {}
with open('data/new_opening_hours') as f:
    for line in f.readlines():
        data = [item.strip() for item in line.split('|')]
        office_names[data[0]] = data[1]

# write out these files
hours_out = 'data/selection.hours'
osm_out = 'data/selection.osm'
osc_out = 'data/selection.osc'

hours_file = open(hours_out, 'w')

def keep(child):
    ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
    return ref == '15854A'

# keep a selection
root = ET.fromstring(response)
tree = ET.ElementTree(root)
count = 0
for child in list(root):
    if child.tag == 'node' or child.tag == 'way':
        if not keep(child):
            root.remove(child)
            continue
        count += 1
        ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        opening_hours = child.find("./tag[@k='opening_hours']").get('v')
        office_name = ''
        if ref in office_names:
            office_name = office_names[ref]
        hours_file.write(ref + "|" + office_name + "|" + opening_hours + "\n")
    elif child.tag == 'relation':
        root.remove(child)

if count == 0:
    print("nothing to upload")
    if os.path.exists(osm_out):
        os.remove(osm_out)
    if os.path.exists(osc_out):
        os.remove(osc_out)
else:
    print(str(count) + " change(s) to upload")
    tree.write(osm_out, 'unicode', True)
    # Create data/selection.osc
    subprocess.call(["python3", "../osm-bulk-upload/osm2change.py", osm_out])

hours_file.close()

