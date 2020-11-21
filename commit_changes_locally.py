#!/usr/bin/env python3
import os

# Newly uploaded (TODO pass as parameter)
hours_file = 'data/selection.hours'

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
            hours_dict[data[0]] = data[2]
            print("DB " + data[0])

# Merge the newly uploaded files into the DB
with open(hours_file) as f:
    for line in f.readlines():
        data = [item.strip() for item in line.split('|')]
        hours_dict[data[0]] = data[2]
        print(hours_file + " " + data[0])

# Save back the DB
with open(local_db, "w") as f:
    for ref in sorted(hours_dict.keys()):
        f.write(ref + "|" + office_names[ref] + "|" + hours_dict[ref] + "\n")
