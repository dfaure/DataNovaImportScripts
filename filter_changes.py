#!/usr/bin/env python3
import os
import subprocess
import shutil
import copy
import math
import xml.etree.ElementTree as ET

# Parse office id -> office name dict, to keep .hours files readable
office_names = {}
with open('data/new_opening_hours') as f:
    for line in f.readlines():
        data = [item.strip() for item in line.split('|')]
        office_names[data[0]] = data[1]

# Prepare output dir
if os.path.exists('changes'):
    shutil.rmtree('changes')
os.mkdir('changes')

class CurrentOutput:
    file_counter = 0           # C++ static
    object_counter = 0         # C++ static
    def __init__(self, root):
        self.hours_out = 'changes/' + str(CurrentOutput.file_counter) + '.hours'
        self.osm_out = 'changes/' + str(CurrentOutput.file_counter) + '.osm'
        self.hours_file = open(self.hours_out, 'w')
        self.xmlroot = ET.Element(root.tag)
        self.xmlroot.attrib = copy.deepcopy(root.attrib)
        self.count = 0

    def write_and_close(self):
        self.hours_file.close()
        if self.count > 0:
            CurrentOutput.object_counter += self.count
            ET.ElementTree(self.xmlroot).write(self.osm_out, 'unicode', True)
            # Create the corresponding ".osc" file
            subprocess.call(["python3", "../osm-bulk-upload/osm2change.py", self.osm_out])
            CurrentOutput.file_counter += 1

    def keep(self, child):
        if child.get('action') != 'modify':
            return False
        #ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
        #return ref == '15854A'
        return True

    def add(self, child, ref, office_name):
        # https://stackoverflow.com/questions/15527399/python-elementtree-inserting-a-copy-of-an-element
        self.xmlroot.append(ET.ElementTree(child).getroot())

        self.hours_file.write(ref + "|" + office_name + "|" + opening_hours + "\n")
        self.count += 1

    def enlarge_area(self, child, office_name):
        lat_str = child.get('lat')
        lon_str = child.get('lon')
        if lat_str is None or lon_str is None:
            center = child.find("center")
            if center is None:
                print('No lat/lon nor center for id ' + child.get('id'))
            lat_str = center.get('lat')
            lon_str = center.get('lon')
        if lat_str is None or lon_str is None:
            print('Missing lat/lon for id ' + child.get('id'))
        #print('{}, {}, {}'.format(office_name, lat_str, lon_str))
        lat = float(lat_str)
        lon = float(lon_str)
        if self.count == 0:
            self.min_lat = lat
            self.max_lat = lat
            self.min_lon = lon
            self.max_lon = lon
        else:
            self.min_lat = min(self.min_lat, lat)
            self.max_lat = max(self.max_lat, lat)
            self.min_lon = min(self.min_lon, lon)
            self.max_lon = max(self.max_lon, lon)

    # area = (pi/180)R^2 |sin(lat1)-sin(lat2)| |lon1-lon2|
    # http://mathforum.org/library/drmath/view/63767.html
    def area(self):
        size = math.pi * 2 * 6357 * 6357 * abs(math.sin(math.radians(self.max_lat)) - math.sin(math.radians(self.min_lat))) * abs(self.max_lon - self.min_lon) / 360
        #print('  lat {} - {}, lon {} - {} => area {}'.format(self.min_lat, self.max_lat, self.min_lon, self.max_lon, size))
        return size

# open the full output from process_post_offices.py
tree = ET.parse('data/osm_post_offices.osm')
root = tree.getroot()

current_out = CurrentOutput(root)

for child in root:
    if child.tag == 'node' or child.tag == 'way':
        if current_out.keep(child):
            ref = child.find("./tag[@k='ref:FR:LaPoste']").get('v')
            opening_hours = child.find("./tag[@k='opening_hours']").get('v')
            office_name = ''
            if ref in office_names:
                office_name = office_names[ref]

            current_out.enlarge_area(child, office_name)
            if current_out.area() > 500: # km^2
                current_out.write_and_close()
                #print('starting new chunk')
                current_out = CurrentOutput(root)
                current_out.enlarge_area(child, office_name) # initialize with this one
            current_out.add(child, ref, office_name)

current_out.write_and_close()

if CurrentOutput.file_counter == 0:
    print("nothing to upload")
else:
    print(str(CurrentOutput.file_counter) + " file(s) created, to upload changes to " + str(CurrentOutput.object_counter) + " object(s)")
