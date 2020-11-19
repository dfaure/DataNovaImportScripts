#!/usr/bin/env python3
import subprocess
# https://docs.python.org/3/library/xml.etree.elementtree.html#module-xml.etree.ElementTree
import xml.etree.ElementTree as ET

# open the full output from process_post_offices.py
xmlfile = open("data/osm_post_offices.osm", "r")
response = xmlfile.read()

def keep(ref):
    return ref == '15930A'

# keep a selection
root = ET.fromstring(response)
tree = ET.ElementTree(root)
for child in list(root):
    if child.tag == 'node' or child.tag == 'way':
        ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        if not keep(ref):
            root.remove(child)
            continue
    elif child.tag == 'relation':
        root.remove(child)

tree.write('data/selection.osm', 'unicode', True)

subprocess.call(["python3", "../osm-bulk-upload/osm2change.py", "data/selection.osm"])

