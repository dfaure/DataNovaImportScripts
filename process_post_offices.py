#!/usr/bin/env python3
# https://docs.python.org/3/library/xml.etree.elementtree.html#module-xml.etree.ElementTree
import xml.etree.ElementTree as ET
# https://github.com/rezemika/oh_sanitizer
from oh_sanitizer import sanitize_field

xmlfile = open("data/osm_post_offices.xml", "r")
response = xmlfile.read()

# parse opening hours generated from the perl script
hours_dict = {}
office_names = {}
with open('data/new_opening_hours') as f:
    lines = f.readlines() # list containing lines of file
    for line in lines:
        data = [item.strip() for item in line.split('|')]
        hours_dict[data[0]] = data[2]
        office_names[data[0]] = data[1]

# parse XML
root = ET.fromstring(response)
tree = ET.ElementTree(root)
for child in root:
    if child.tag == 'node' or child.tag == 'way':
        ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        old_opening_hours = child.find("./tag[@k='opening_hours']")
        if not ref in hours_dict:
            print("Not in datanova: " + ref)
        else:
            new_opening_hours = hours_dict[ref]
            if "ERROR" in new_opening_hours:
                print("In datanova but not ready: " + ref + ": " + new_opening_hours)
            else:
                new_opening_hours = sanitize_field(new_opening_hours)
                if not old_opening_hours is None:
                    print("Old opening hours for " + ref + ": " + sanitize_field(old_opening_hours.get('v')) + " we have " + new_opening_hours)
                else:
                    opening_hours_tag = ET.SubElement(child, 'tag')
                    opening_hours_tag.set('k', 'opening_hours')
                    opening_hours_tag.set('v', new_opening_hours)
                    child.set('action', 'modify')

tree.write('data/osm_post_offices.osm')