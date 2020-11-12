#!/usr/bin/env python3
# https://github.com/mvexel/overpass-api-python-wrapper
import overpass

api = overpass.API(timeout=3000)

# https://wiki.openstreetmap.org/wiki/Overpass_API/Language_Guide#The_Overpass_API_languages
response = api.get('nwr["ref:FR:LaPoste"]["amenity"="post_office"]', responseformat="xml", verbosity='meta')

xmlfile = open("data/osm_post_offices.xml", "w+")
xmlfile.write(response)
