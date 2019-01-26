#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

# Script to take as input as URI and:
#	show each unique domain name
#	try to resolve them and show the IP address.
#
#	Dave O'Brien 20190126
my $verbose = 1;

while (my $url = shift) {
	print "Analysing $url\n" if $verbose;
	my @lines = `curl $url | grep http`;
	my %domains;
	
	foreach my $line (@lines) {
		chomp $line;
		print "$line\n" if $verbose;
		my @domains = ( $line =~ /:\/\/(.*?)\//g);
		foreach my $domain (@domains) {
			$domains{$domain}++;
			print "\t$domain: $domains{$domain}\n" if $verbose;
		}
	}
	
	foreach my $domain (keys %domains) {
		if (exists($domains{$domain}) ) {
			my $ip = `dig +short $domain`;
			chomp $ip;
			print "Domain: $domain $ip\n\n";
		}
	}
}