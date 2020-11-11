#!/usr/bin/env python3
# https://github.com/mvexel/overpass-api-python-wrapper
import overpass

api = overpass.API(timeout=3000)
# TODO remove ="15940A"
response = api.get('nwr["ref:FR:LaPoste"="15940A"]["amenity"="post_office"]', responseformat="xml", verbosity='meta')

xmlfile = open("data/osm_post_offices.xml", "w+")
xmlfile.write(response)

