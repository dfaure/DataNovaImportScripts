#!/usr/bin/env python3
# https://docs.python.org/3/library/xml.etree.elementtree.html#module-xml.etree.ElementTree
import xml.etree.ElementTree as ET
import dateutil.parser as dateparser
import datetime
import os

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
            id = data[0]
            saved_hours_dict[id] = data[2]
            saved_office_names[id] = data[1]
            if id in office_names and office_names[id] != saved_office_names[id]:
                print("NOTE: " + id + " was " + saved_office_names[id] + " but now it's " + office_names[id])

# parse list of changes to be overwritten
force = {}
if os.path.isfile('force.txt'):
    with open('force.txt') as f:
        lines = f.readlines() # list containing lines of file
        for line in lines:
            id = line.strip()
            force[id] = 1


def old_special_days_removed(old_opening_hours, new_opening_hours):
    # old: Mo-Fr 09:00-12:00,14:00-17:00; Sa 09:00-12:00; PH off; 2020 Dec 31,2021 Jan 05 09:00-12:00
    # new: Mo-Fr 09:00-12:00,14:00-17:00; Sa 09:00-12:00; PH off; 2021 Jan 05 09:00-12:00
    if 'ERROR' in old_opening_hours or 'ERROR' in new_opening_hours:
        return False;
    #print(old_opening_hours + '\nnew=' + new_opening_hours)
    pos_old = old_opening_hours.find('PH off')
    pos_new = new_opening_hours.find('PH off')
    if pos_old < 0 or pos_new < 0 or pos_old != pos_new:
        return False
    old_left = old_opening_hours[:pos_old+6]
    new_left = new_opening_hours[:pos_new+6]
    if old_left != new_left:
        #print(old_left + ' != ' + new_left)
        return False;
    old_right = old_opening_hours[pos_old+8:]
    new_right = new_opening_hours[pos_new+8:]
    if not old_right.endswith(new_right):
        #print(old_right + ' does not end with ' + new_right)
        return False
    now = datetime.datetime.now()
    removed_str = old_right[:len(old_right)-len(new_right)]
    if removed_str.endswith('; '):
        removed_str = removed_str[:-2]
    for removed_dates in removed_str.split(';'):
        #print('REMOVED_DATES ' + removed_dates)
        for removed in removed_dates.split(','):
            colon = removed.find(':')
            if colon > -1: # e.g. 2020 Dec 31 07:30-12:00
                if colon == 2:
                    continue
                removed = removed[:colon-3]
            if ':' in removed: # shouldn't happen anymore
                print("COMPLICATED " + removed)
                return False
            if removed != '':
                try:
                    date = dateparser.parse(removed)
                except:
                    return False
                if date > now: # A change for a date in the future? Upload it.
                    return False
    return True

# parse XML
root = ET.fromstring(response)
tree = ET.ElementTree(root)
seen_refs = {}
for child in root:
    if child.tag == 'node' or child.tag == 'way':
        ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        id = child.get('id')
        deepurl = "https://osmlab.github.io/osm-deep-history/#/"  + child.tag + '/' + id
        changed = False
        if ref in seen_refs:
            print("OSM error: duplicate ref " + ref + ' used in https://www.openstreetmap.org/' + seen_refs[ref] + ' and https://www.openstreetmap.org/' + child.tag + '/' + id + ' - check with https://www.laposte.fr/particulier/outils/trouver-un-bureau-de-poste/bureau-detail/' + ref + '/' + ref)
        seen_refs[ref] = child.tag + '/' + id
        if not ref in hours_dict:
            print("Not in datanova: " + ref + ' see https://www.openstreetmap.org/' + child.tag + '/' + id)
        else:
            new_opening_hours = hours_dict[ref]
            if "ERROR" in new_opening_hours:
                print(ref + ": in datanova but not ready (parser failed): " + new_opening_hours)
            else:
                old_opening_hours_tag = child.find("./tag[@k='opening_hours']")
                if not old_opening_hours_tag is None:
                    old_opening_hours = old_opening_hours_tag.get('v')
                    old_vs_new = ref + ":   OSM " + old_opening_hours + "\n" + ref + ":   now " + new_opening_hours
                    if old_opening_hours + "; PH off" == new_opening_hours:
                        print(ref + ": missing PH off, adding")
                        old_opening_hours_tag.set('v', new_opening_hours)
                        child.set('X-reason', 'ph_off_') # for filter_changes.py
                        changed = True
                    elif old_opening_hours == new_opening_hours:
                        print(ref + ": agree")
                    elif new_opening_hours.startswith(old_opening_hours + "; PH off"):
                        print(ref + ": missing PH off and special days, adding\n" + old_vs_new)
                        old_opening_hours_tag.set('v', new_opening_hours)
                        child.set('X-reason', 'ph_off_special_days_') # for filter_changes.py
                        changed = True
                    elif old_special_days_removed(old_opening_hours, new_opening_hours):
                        print(ref + ": only old special days removed, agree\n" + old_vs_new)
                    elif ref in force:
                        print(ref + ": repairing former problem after no external change, see " + deepurl)
                        old_opening_hours_tag.set('v', new_opening_hours)
                        child.set('X-reason', 'update_') # for filter_changes.py
                        changed = True
                    elif ref in saved_hours_dict:
                        saved_opening_hours = saved_hours_dict[ref]
                        saved_vs_new = ref + ":   was " + saved_opening_hours + "\n" + ref + ":   now " + new_opening_hours
                        if old_opening_hours == saved_opening_hours:
                            print(ref + ": datanova changed and OSM was untouched meanwhile, replacing.\n" + saved_vs_new)
                            old_opening_hours_tag.set('v', new_opening_hours)
                            child.set('X-reason', 'update_') # for filter_changes.py
                            changed = True
                        elif saved_opening_hours == new_opening_hours:
                            print(ref + ": no change in datanova, still " + saved_opening_hours + " but OSM was modified meanwhile, to " + old_opening_hours + ", skipping. " + deepurl)
                        else:
                            print(ref + ": datanova changed from " + saved_opening_hours + " to " + new_opening_hours + " but OSM was modified by a human meanwhile, to " + old_opening_hours + ", skipping. See " + deepurl)
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
                    old_opening_hours_covid_tag = child.find("./tag[@k='opening_hours:covid19']")
                    old_timestamp = child.get("timestamp") < '2020-05-01'
                    if not old_opening_hours_covid_tag is None and old_opening_hours_covid_tag.get('v') != "open":
                        if old_timestamp or ref in force:
                            print(ref + ": overriding covid entry due to old timestamp and no opening_hours in OSM. See " + deepurl)
                            opening_hours_tag = ET.SubElement(child, 'tag')
                            opening_hours_tag.set('k', 'opening_hours')
                            opening_hours_tag.set('v', new_opening_hours)
                            child.remove(old_opening_hours_covid_tag)
                            changed = True
                        else:
                            old_opening_hours_covid = old_opening_hours_covid_tag.get('v')
                            if old_opening_hours_covid == new_opening_hours:
                                print(ref + ": no opening_hours but covid hours match: " + old_opening_hours_covid)
                            else:
                                print(ref + ": no opening_hours but covid hours: " + old_opening_hours_covid + ', datanova: ' + new_opening_hours + ', see ' + deepurl)

                    else:
                        print(ref + ": no opening_hours in OSM, adding")
                        opening_hours_tag = ET.SubElement(child, 'tag')
                        opening_hours_tag.set('k', 'opening_hours')
                        opening_hours_tag.set('v', new_opening_hours)
                        if not old_opening_hours_covid_tag is None:
                            child.remove(old_opening_hours_covid_tag)
                        changed = True
        if changed:
            child.set('action', 'modify')

tree.write('data/osm_post_offices.osm', 'unicode', True)
