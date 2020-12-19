#!/usr/bin/env python3
import os
import sys

if len(sys.argv) < 2:
    sys.stderr.write("Synopsis:\n")
    sys.stderr.write("    %s <file-name.hours> [<file-name.hours>...]\n" % (sys.argv[0],))
    sys.exit(1)

filenames = []
for arg in sys.argv[1:]:
    # There's room for adding support for options here
    filenames.append(arg)

# parse office id -> office name dict, to keep .hours files readable
office_names = {}
with open('data/new_opening_hours') as f:
    for line in f.readlines():
        data = [item.strip() for item in line.split('|')]
        office_names[data[0]] = data[1]

# Our local DB
local_db = 'saved_opening_hours'

hours_dict = {}
with open(local_db) as f:
    for line in f.readlines():
        data = [item.strip() for item in line.split('|')]
        if len(data) < 3:
            print("ERROR: invalid line " + line)
        else:
            id = data[0]
            hours_dict[id] = data[2]
            if id not in office_names:
                office_names[id] = data[1]
            #print("DB " + id)

# Merge the newly uploaded files into the DB
for hours_file in filenames:
    with open(hours_file) as f:
        for line in f.readlines():
            data = [item.strip() for item in line.split('|')]
            hours_dict[data[0]] = data[2]
            #print(hours_file + " " + data[0])

# Save back the DB
with open(local_db + ".new", "w") as f:
    for ref in sorted(hours_dict.keys()):
        f.write(ref + "|" + office_names[ref] + "|" + hours_dict[ref] + "\n")
os.rename(local_db + ".new", local_db)
