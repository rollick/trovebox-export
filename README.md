# Trovebox Export

## What does it do?

The script will download all photos associated with a Trovebox account into separate directories grouped by album, year and then month. Some extra metadata from Trovebox will be added to the IPTC data in the photo. These fields will be added if present:

* title 
* description
* keywords

Finally, a copy of the Trovebox API response is stored per album to a file named album.json.

## Using this script (Ruby/bundler required)

* update settings in default.yml
* bundle install
* ./fetch.rb