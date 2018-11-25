#!/usr/bin/perl
use strict;
use warnings;
use WWW::Mechanize;

# Script to automatically download the blocklists from the PiHole project and
# Convert them to zone files for use with Bind.
#
# (C) Dave O'Brien, 20180407

# Options
my $verbose = 1;
my $download = 0;
my $zone_limit = 1000000; # how many zones in the file
my ($ticked, $uncrossed, $all) = (1,0,0);


my @lists;
if ( $download ) {
    @lists = get_lists();
} else {
    #have a locally stored list for testing (-1 for all lists, )
    @lists = get_lists_locally(-1);
}
print "@lists" if $verbose;

my @domains = parse_lists (@lists);
open (my $fh, ">", "adblock_named.file");
my @whitelists = whitelist();
my $count = 0;
foreach my $domain (@domains) {
    my $address_ok = 1;
    # Check for reasons to not printout the line
    if ( length($domain) < 1) { $address_ok = 0; }
    foreach my $whitelist (@whitelists) {
        if ($domain =~ /$whitelist/) {
            $address_ok = 0;
        }
    }
    if ($count <= $zone_limit) {
        my $zoneline = "zone \"$domain\" { type master; notify no; file \"named.adblock\"; allow-query { allowed; }; };";
        print "\t$count: $zoneline\n" if $verbose;
        print $fh "$zoneline\n" if $address_ok;
        $count++;
    }
}

close $fh;

sub get_lists {
    # Fetches a list of host files from three urls and downloads each file
    my @lists;
    my @blocklists;
    # Lists from here: https://v.firebog.net/hosts/lists.php
    push @lists, "https://v.firebog.net/hosts/lists.php?type=tick" if $ticked;
    push @lists, "https://v.firebog.net/hosts/lists.php?type=nocross" if $uncrossed;
    push @lists, "https://v.firebog.net/hosts/lists.php?type=all" if $all;
    my $agent =  WWW::Mechanize->new( autocheck => 1);
    foreach my $list (@lists) {
        print "Retrieving $list..." if $verbose;
        $agent->get($list);
        if ($agent->success) {
            my @urls = split("\n", $agent->content());
            push @blocklists, @urls;
            print "$#urls added.\n" if $verbose;
        }
    }
    # foreach list, put the list into an array @urls, and check for duplicates.
    # then, download each list and put the individual entries into an array
    #print join ", ", @blocklists;
    return @blocklists;
}

sub parse_lists {
	#Takes a list of URLS that are each in the form of a HOSTS file (IP\tDomain NAME)
	# and returns a named conf file that can be #included
	# This line should have the form:
	#zone "doubleclick.net" { type master; notify no; file "named.empty"; allow-query { allowed; }; };
	my @lists = @_;
	my @domains;
	my %domains;
	my $agent =  WWW::Mechanize->new( autocheck => 1);
	foreach my $list (@lists) {
		print "Getting $list\n" if $verbose;
		$agent->get($list);
		if ($agent->success) {
			if ($download == 0) {
				# save the lists
				my $list_filename = $list;
				$list_filename =~ s/^http[s]*\:\/\///g;
				$list_filename =~ s#\/#_#g;
				open ( my $listfh, ">", "lists/" . $list_filename);
				print $listfh $agent->content();
				close $listfh;
			}
			my @urls = split("\n", $agent->content());
			foreach my $line (@urls) {
				chomp ($line);
				$line = lc(sanitize($line));
				print "\tLine: '$line':" if $verbose;
				my $domain = "";
				# check for comments
				if ($line =~ /^\#+/ ) { } #comment, ignore }
				# check for a.b.c.d	hostname
				if ($line =~ /^([0-9a-f.:]+)[ \t]+(.*)$/ ) { $domain = $2; 	}
				# check for just a hostname
				if ($line =~ /^([a-z0-9.-]+)$/ ) { $domain = $1;}
				# remove trailing comments on some domains
				if ( $domain =~ /([#]+.*$)/) { 
					$domain =~ s/$1//g; 
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
					push @domains, $domain if ($domains{$domain}<2);
				}
				print "\n" if $verbose;
			}
		}
	}
	return @domains;
}

sub whitelist {
	# return the list of recommended whitelist URLs.
	my @whitelist;
	push @whitelist, "s3.amazonws.com";
	push @whitelist, "clients2.google.com";
	push @whitelist, "clients3.google.com";
	push @whitelist, "clients4.google.com";
	push @whitelist, "clients5.google.com";
	push @whitelist, "www.bit.ly";
	push @whitelist, "bit.ly";
	push @whitelist, "ow.ly";
	push @whitelist, "j.mp";
	push @whitelist, "goo.gl";
	push @whitelist, "msftncsi.com";
	push @whitelist, "www.msftncsi.com";
	push @whitelist, "ea.com";
	push @whitelist, "cdn.optimizely.com";
	push @whitelist, "res.cloudinary.com";
	push @whitelist, "gravatar.com";
	push @whitelist, "rover.ebay.com";
	push @whitelist, "imgs.xkcd.com";
	push @whitelist, "netflix.com";
	push @whitelist, "alluremedia.com.au ";
	push @whitelist, "tomshardware.com";
	push @whitelist, "s.shopify.com";
	push @whitelist, "keystone.mwbsys.com";
	push @whitelist, "dl.dropbox.com";
	push @whitelist, "api.ipify.org";
	push @whitelist, "localhost";
	push @whitelist, "microsoft.com";
	push @whitelist, "google.com";
	push @whitelist, "diaspoir.net";
	push @whitelist, "zdbb.net";
	push @whitelist, "prf.hn"; # some marketing bullshit that iMore refuses to run without
	push @whitelist, "s1.wp.com"; # needed for WP hosted stylesheets
	push @whitelist, "stats.wp.com"; # WP Hosted Stats
	push @whitelist, "cpan.org"; # CPAN
	push @whitelist, "www.linkedin.com"; # CPAN
	push @whitelist, "ads.linkedin.com"; # CPAN
	push @whitelist, "cedexis.net"; # CPAN
	push @whitelist, "list-manage.com"; # CPAN
	return @whitelist;
}
sub get_lists_locally {
	my $list = shift; 
	my @lists = split ", ", "https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.Spam/hosts, https://v.firebog.net/hosts/static/w3kbl.txt, https://adaway.org/hosts.txt, https://v.firebog.net/hosts/AdguardDNS.txt, https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt, https://hosts-file.net/ad_servers.txt, https://v.firebog.net/hosts/Easylist.txt, https://raw.githubusercontent.com/CHEF-KOCH/Spotify-Ad-free/master/Spotifynulled.txt, https://raw.githubusercontent.com/StevenBlack/hosts/master/data/UncheckyAds/hosts, https://v.firebog.net/hosts/Airelle-trc.txt, https://v.firebog.net/hosts/Easyprivacy.txt, https://v.firebog.net/hosts/Prigent-Ads.txt, https://raw.githubusercontent.com/quidsup/notrack/master/trackers.txt, https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.2o7Net/hosts, https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/win10/spy.txt, https://v.firebog.net/hosts/Airelle-hrsk.txt, https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt, https://mirror1.malwaredomains.com/files/justdomains, https://hosts-file.net/exp.txt, https://hosts-file.net/emd.txt, https://hosts-file.net/psh.txt, https://mirror.cedia.org.ec/malwaredomains/immortal_domains.txt,  https://bitbucket.org/ethanr/dns-blacklists/raw/8575c9f96e5b4a1308f2f12394abd86d0927a4a0/bad_lists/Mandiant_APT1_Report_Appendix_D.txt, https://v.firebog.net/hosts/Prigent-Malware.txt, https://v.firebog.net/hosts/Prigent-Phishing.txt, https://raw.githubusercontent.com/quidsup/notrack/master/malicious-sites.txt, https://ransomwaretracker.abuse.ch/downloads/RW_DOMBL.txt, https://v.firebog.net/hosts/Shalla-mal.txt, https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.Risk/hosts, https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist";
	 #http://jansal.googlecode.com/svn/trunk/adblock/hosts, http://www.sa-blacklist.stearns.org/sa-blacklist/sa-blacklist.current, https://easylist-downloads.adblockplus.org/malwaredomains_full.txt, https://easylist-downloads.adblockplus.org/easyprivacy.txt, https://easylist-downloads.adblockplus.org/easylist.txt, https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt, http://www.fanboy.co.nz/adblock/opera/urlfilter.ini, 	http://www.fanboy.co.nz/adblock/fanboy-tracking.txt";
	if ($list == -1) {
		return @lists;
	} else {
		return $lists[$list];
	}
}

sub sanitize {
	my $input = shift;
	$input =~ s/\x0d$//;
	$input =~ s/[^[:ascii:]]//; #non-ascii characters
	return $input;
}
