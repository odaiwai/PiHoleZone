#!/usr/bin/perl
use strict;
use warnings;

# Script to automatically download the blocklists from the PiHole project and 
# Convert them to zone files for use with Bind.
#
# (C) Dave O'Brien, 20180407

my $verbose = 1;
