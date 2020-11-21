#!/usr/bin/env python3
# https://docs.python.org/3/library/xml.etree.elementtree.html#module-xml.etree.ElementTree
import xml.etree.ElementTree as ET
# https://github.com/rezemika/oh_sanitizer
# Slow, doesn't change anything on our generated data, and breaks if bad data in OSM
#from oh_sanitizer import sanitize_field

xmlfile = open("data/osm_post_offices.xml", "r")
response = xmlfile.read()

# parse opening hours generated from the perl script
hours_dict = {}
office_names = {}
with open('data/new_opening_hours') as f:
    lines = f.readlines() # list containing lines of file
    for line in lines:
        data = [item.strip() for item in line.split('|')]
        if len(data) < 3:
            print("ERROR: invalid line " + line)
        else:
            hours_dict[data[0]] = data[2]
            office_names[data[0]] = data[1]

# parse opening hours previously uploaded by our scripts
saved_hours_dict = {}
saved_office_names = {}
with open('saved_opening_hours') as f:
    lines = f.readlines() # list containing lines of file
    for line in lines:
        data = [item.strip() for item in line.split('|')]
        if len(data) < 3:
            print("ERROR: invalid line " + line)
        else:
            saved_hours_dict[data[0]] = data[2]
            saved_office_names[data[0]] = data[1]
            if office_names[data[0]] != saved_office_names[data[0]]:
                print("NOTE: " + data[0] + " was " + saved_office_names[data[0]] + " but now it's " + office_names[data[0]])

# parse XML
root = ET.fromstring(response)
tree = ET.ElementTree(root)
for child in root:
    if child.tag == 'node' or child.tag == 'way':
        ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        old_opening_hours_tag = child.find("./tag[@k='opening_hours']")
        id = child.get('id')
        changed = False
        if not ref in hours_dict:
            print("Not in datanova: " + ref + ' see https://www.openstreetmap.org/' + child.tag + '/' + id)
        else:
            new_opening_hours = hours_dict[ref]
            if "ERROR" in new_opening_hours:
                print(ref + ": in datanova but not ready (parser failed): " + new_opening_hours)
            else:
                if not old_opening_hours_tag is None:
                    old_opening_hours = old_opening_hours_tag.get('v')
                    if old_opening_hours + "; PH off" == new_opening_hours:
                        print(ref + ": missing PH off, adding")
                        old_opening_hours_tag.set('v', new_opening_hours)
                        changed = True
                    elif old_opening_hours == new_opening_hours:
                        print(ref + ": agree")
                    elif ref in saved_hours_dict:
                        saved_opening_hours = saved_hours_dict[ref]
                        if old_opening_hours == saved_opening_hours:
                            print(ref + ": datanova changed from " + saved_opening_hours + " to " + new_opening_hours + " and OSM was untouched meanwhile, replacing")
                            old_opening_hours_tag.set('v', new_opening_hours)
                            changed = True
                        else:
                            print(ref + ": datanova changed from " + saved_opening_hours + " to " + new_opening_hours + " but OSM was modified meanwhile, to " + old_opening_hours + ", skipping. See https://osmlab.github.io/osm-deep-history/#/"  + child.tag + '/' + id)
                    else:
                        print(ref + ": OSM says " + old_opening_hours + " datanova says " + new_opening_hours + " leaving untouched for now")

                        #fixme_tag = child.find("./tag[@k='fixme']")
                        #fixme_str="horaires à vérifier, voir si suggested:opening_hours contient la bonne valeur."
                        #if not fixme_tag is None:
                        #    fixme_tag.set('v', fixme_tag.get('v') + '; ' + fixme_str)
                        #else:
                        #    fixme_tag = ET.SubElement(child, 'tag')
                        #    fixme_tag.set('k', 'fixme')
                        #    fixme_tag.set('v', fixme_str)
                        #suggestion_tag = child.find("./tag[@k='suggested:opening_hours']")
                        #if not suggestion_tag is None:
                        #    suggestion_tag.set('v', new_opening_hours)
                        #else:
                        #    suggestion_tag = ET.SubElement(child, 'tag')
                        #    suggestion_tag.set('k', 'suggested:opening_hours')
                        #    suggestion_tag.set('v', new_opening_hours)
                        #changed = True
                else:
                    print(ref + ": no opening_hours in OSM, adding")
                    opening_hours_tag = ET.SubElement(child, 'tag')
                    opening_hours_tag.set('k', 'opening_hours')
                    opening_hours_tag.set('v', new_opening_hours)
                    changed = True
        if changed:
            child.set('action', 'modify')

tree.write('data/osm_post_offices.osm', 'unicode', True)
