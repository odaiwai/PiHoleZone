#!/bin/bash

time ./make_pihole_zone.pl > make_pihole_zone.log
cat adblock_named.file | sort | uniq > adblock_named.sort
sudo cp adblock_named.sort /var/named/
sudo chown named.named /var/named/adblock_named.sort
echo "Checking the config file..."
sudo named-checkconf -z /etc/named.conf > checkconf.log
