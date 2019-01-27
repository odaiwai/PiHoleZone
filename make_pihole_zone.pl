#!/usr/bin/perl
use strict;
use warnings;
use WWW::Mechanize;

# my own library
use lib "/home/odaiwai/src/dob_DBHelper";
use DBHelper;

# Script to automatically download the blocklists from the PiHole project and
# Convert them to zone files for use with Bind.
#
# (C) Dave O'Brien, 20180407

# Options
my $verbose = 1;
my $download = 0;
my $zone_limit = 1000000; # how many zones in the file
my ($ticked, $uncrossed, $all) = (1,0,0);

# initialise the database
my $dbname = "pihole.sqlite";
my $db = dbconnect($dbname);

# If we're downloading, rebuild the database from scratch
if ( $download ) {
    my $num_tables = create_db($db);
    my @lists = get_lists();
    print "@lists" if $verbose;
    my @domains = parse_lists (@lists);
    
}

# Apply the whitelist - do this here to allow for changes to the whitelist without
# downloading everthing.
my @whitelists = whitelist();
my @urls = array_from_query( $db, "select url from [entries] group by url;", $verbose);

# Go through the list
my $result = dbdo( $db, "BEGIN", $verbose);
foreach my $url (@urls) {
    # check if it's on the whitelist
    my $whitelisted = 0;
    my @reasons;
    foreach my $whitelist (@whitelists) {
        if ($url =~ /$whitelist$/) {
            $whitelisted++;
            push @reasons, $whitelist;
        }
    }
    if ( $whitelisted > 0 ) {
        my $reasons = join ";", @reasons;
        print "\t$url: $whitelisted ($reasons)\n" if $verbose;
        my $result = dbdo($db, "Update [Entries] set whitelist = $whitelisted, reasons = \"$reasons\" where URL = \'$url\';", $verbose);
    } 
}
$result = dbdo( $db, "COMMIT", $verbose);

# Make the named.file
open (my $fh, ">", "adblock_named.file");
my $count = 0;

# Get the list of domains
my $query = querydb( $db, "select url, source, ticked, whitelist from [entries] where (Ticked = 1 and Whitelist = 0) group by url;", $verbose);
while (my @row = $query->fetchrow_array) {
    my ($url, $source, $ticked, $whitelist) = @row;
    my $zoneline = "zone \"$url\" { type master; notify no; file \"named.adblock\"; allow-query { allowed; }; }; # $source";
    print "\t$zoneline\n" if $verbose;
    print $fh "$zoneline\n";
    $count++;
}

close $fh;

sub get_lists {
    # Fetches a list of host files from three urls and downloads each file
    my @lists;
    my @blocklists;
    my @categories = qw/all_lists uncrossed ticked/;
    
    # Lists from here: https://v.firebog.net/hosts/lists.php
    $lists[0] = "https://v.firebog.net/hosts/lists.php?type=all";   
    $lists[1] = "https://v.firebog.net/hosts/lists.php?type=nocross";
    $lists[2] = "https://v.firebog.net/hosts/lists.php?type=tick";    
    
    # 
    my $idx = 0;
    my %lists;
    
    my $agent =  WWW::Mechanize->new( autocheck => 1);
    foreach my $list (@lists) {
        print "Retrieving $list..." if $verbose;
        $agent->get($list);
        if ($agent->success) {
            my @urls = split("\n", $agent->content());
            my $category = $categories[$idx];
            
            # store the urls
            my $result = dbdo( $db, "BEGIN", $verbose);
            foreach my $url (@urls) {
                $lists{$url}++;
                # for the all list, set to 0,0,1 as the entry is almost certainly not in the database
                if ( $idx == 0 ) {
                    my $result = dbdo($db, "Insert or ignore into [Lists] (URL, ticked, uncrossed, all_lists) Values (\"$url\", 0, 0, 1);", $verbose);
                    push @blocklists, $url;
                } else {
                    # check if the URL is already in the dbase:
                    if ( exists($lists{$url}) ) {
                        my $result = dbdo($db, "Update [Lists] set $category = 1 where URL = \'$url\';", $verbose);
                    } else {
                        my $result = dbdo($db, "Insert or ignore into [Lists] (URL, $category) Values (\"$url\", 1);", $verbose);
                    }
                }
            }
            $result = dbdo( $db, "COMMIT", $verbose);
            print "$#urls added.\n" if $verbose;
        }
        $idx++;
    }
    # foreach list, put the list into an array @urls, and check for duplicates.
    # then, download each list and put the individual entries into an array
    #print join ", ", @blocklists;
    return @blocklists;
}

sub create_db {
    my $db = shift;
	drop_all_tables($db, "", $verbose); # Middle var is prefix, for dropping tables of the form
                                        # apple_this, apple_that, etc, where 'apple' is the prefix
     
    my %tables;
    $tables{"lists"} = "URL Text, Ticked Integer, Uncrossed Integer, All_lists Integer";
    $tables{"entries"} = "URL Text Primary Key, Source TEXT, Count Integer, Comment TEXT, Ticked Integer, Uncrossed Integer, All_lists Integer, Whitelist Integer, reasons TEXT";
    my $num_tables = make_db($db, \%tables, $verbose);
    my $result = dbdo($db, "vacuum", $verbose);
    
    return $num_tables;
}

sub parse_lists {
    #Takes a list of URLS that are each in the form of a HOSTS file (IP\tDomain NAME)
    # and returns a named conf file that can be #included
    # This line should have the form:
    #zone "doubleclick.net" { type master; notify no; file "named.empty"; allow-query { allowed; }; };
    my @lists = @_;
    my @domains;
    my %domains;
    my @whitelist = whitelist();
    
    my $agent =  WWW::Mechanize->new( autocheck => 1);
    foreach my $list (@lists) {
        print "Getting $list\n" if $verbose;
        
        # Get it's classification from the dbase;
        my @row = row_from_query($db, "select Ticked, Uncrossed, All_lists from [Lists] where url = '$list';", $verbose);
        my ($ticked, $uncrossed, $all) = @row;
        print "\t$list: $ticked, $uncrossed, $all\n" if $verbose;
        
        $agent->get($list);
        if ($agent->success) {
            my @urls = split("\n", $agent->content());
            
            # Parse each list as a separate transaction
            my $result = dbdo( $db, "BEGIN", $verbose);
            foreach my $line (@urls) {
                chomp ($line);
                $line = lc(sanitize($line));
                print "\tLine: '$line':" if $verbose;
                my $domain  = "";
                my $comment = "";
                
                # Check for the various types of record:
                if ($line =~ /^\#+/ ) {
                    # general comment, ignore }
                }
                
                # check for a.b.c.d hostname
                if ($line =~ /^([0-9a-f.:]+)[ \t]+(.*)$/ ) {
                    $domain = $2;
                }
                
                # check for just a hostname
                if ($line =~ /^([a-z0-9.-]+)$/ ) { $domain = $1;}
                
                # remove trailing comments on some domains
                if ( $domain =~ /^(.*)\#(.*)$/) {
                    $domain  = $1;
                    $comment = $2;
                }
                
                # delete domains that are not legal hostnames
                my $domain_legal = 1;
                if ( $domain =~ /^\-|\-$/) { $domain_legal = 0; } # leading/trailing hyphen illegal
                if ( $domain =~ /[\\\?_]+/) { $domain_legal = 0; } # illegal chars
                #if ( $domain =~ /xn\-\-huala/) { $domain_legal = 0; } # illegal chars
                #if ( $domain =~ /hualaihue/) { $domain_legal = 0; } # illegal chars
                #if ( $domain =~ /bireysel/) { $domain_legal = 0; } # no idea
                if ( length($domain) == 0) { $domain_legal = 0; }
                $domain  =~ s/\s+$//g; # remove trailing spaces

                # Add the domain to the list
                if ( $domain_legal ) {
                    $domains{$domain}++;
                    print "\tDomain accepted: $domain ($domains{$domain})" if $verbose;
                    if ($domains{$domain}<2) {
                        # to avoid having multiple entries in the database
                        push @domains, $domain ;
                        
                        # Sanitise comments
                        my $qcomment = $db->quote($comment);
                        
                        my $cmd = "INSERT or Ignore into [Entries] " .
                                  "(URL, Source, Count, Comment, Ticked, Uncrossed, All_Lists, whitelist) " .
                                  "Values (\"$domain\", \"$list\", $domains{$domain}, $qcomment, $ticked, $uncrossed, $all, 0);";
                        my $result = dbdo ( $db, $cmd, $verbose);
                    }
                }
                print "\n" if $verbose;
            }
            $result = dbdo( $db, "COMMIT", $verbose);

        }
    }
    return @domains;
}

sub whitelist {
    # return the list of recommended whitelist URLs.
    my @entries;
    push @entries, "s3.amazonws.com";
    push @entries, ".google.com";
    push @entries, "googleadservices.com";
    push @entries, "www.bit.ly";
    push @entries, "bit.ly";
    push @entries, "ow.ly";
    push @entries, "j.mp";
    push @entries, ".goo.gl";
    push @entries, "msftncsi.com";
    push @entries, "www.msftncsi.com";
    push @entries, ".ea.com";
    push @entries, "cdn.optimizely.com";
    push @entries, "res.cloudinary.com";
    push @entries, ".gravatar.com";
    push @entries, ".ebay.com";
    push @entries, ".xkcd.com";
    push @entries, ".netflix.com";
    push @entries, "maxmind.com";
    push @entries, "alluremedia.com.au ";
    push @entries, ".tomshardware.com";
    push @entries, ".shopify.com";
    push @entries, "keystone.mwbsys.com";
    push @entries, "dl.dropbox.com";
    push @entries, "api.ipify.org";
    push @entries, "localhost";
    push @entries, ".microsoft.com";
    push @entries, "diaspoir.net";
    push @entries, "zdbb.net";
    push @entries, "prf.hn"; # some marketing bullshit that iMore refuses to run without
    push @entries, "s1.wp.com"; # needed for WP hosted stylesheets
    push @entries, "stats.wp.com"; # WP Hosted Stats
    push @entries, "cpan.org"; # CPAN
    push @entries, ".linkedin.com"; #
    push @entries, ".cedexis.net"; #
    push @entries, "list-manage.com"; #
    push @entries, ".opensubtitles.org"; #
    push @entries, "cultofmac.com"; #
    push @entries, "anandtech.com"; #
    push @entries, "tags.news.com.au"; #
    push @entries, ".washingtonpost.com"; #
    push @entries, ".permanenttsb.ie"; #
    push @entries, "redirectingat.com"; #
    push @entries, ".youtu.be"; # youtube
    push @entries, "wistia.net"; #
    push @entries, "purch.com"; #
    push @entries, "cmail20.com"; #
    push @entries, "deadspin.com"; #
    push @entries, "kinja.com"; #
    push @entries, "admob.com"; #
    push @entries, "mailchimp.com"; #
    push @entries, "typepad.com"; #
    push @entries, "clickdimensions.com"; #
    push @entries, "exacttarget.com"; #
    push @entries, "akamaiedge.net"; #
    push @entries, "app.link"; #
    push @entries, "chicdn.net"; #
    push @entries, "scorecardresearch.com"; # interferes with deadspin/kinja
    push @entries, "cdn.digitru.st"; # interferes with deadspin/kinja
    push @entries, "scroll.com"; # interferes with deadspin/kinja
    push @entries, "iopscience.iop.org"; #
    push @entries, "gstatic.com"; # Google Static Domains
    push @entries, "addthis.com"; # Google Static Domains
    
    my @whitelist;
    foreach my $entry (@entries) {
        $entry =~ s/\./\\\./g;
        $entry .= "\$";
        push @whitelist, $entry;
    }
    return @whitelist;        
}

sub sanitize {
    my $input = shift;
    $input =~ s/\x0d$//;
    $input =~ s/[^[:ascii:]]//; #non-ascii characters
    return $input;
}
