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

#my $result = get_ip_from_domain("insight.adsrvr.org");
#print "$result \n";
#exit;

while (my $url = shift) {
	print "Analysing $url\n" if $verbose;
	my @lines = `curl $url | grep http`;
	my %domains;
	
	foreach my $line (@lines) {
		chomp $line;
		#print "$line\n" if $verbose;
		my @domains = ( $line =~ /:\/\/(.*?)\//g);
		foreach my $domain (@domains) {
			$domain =~ s/["'`]+//g;
			$domains{$domain}++;
			#print "\t$domain: $domains{$domain}\n" if $verbose;
		}
	}
	
	foreach my $domain (keys %domains) {
		if (exists($domains{$domain}) ) {
			# Need to parse the output for CNAMES and non-IP returns
			my $ip = get_ip_from_domain($domain);
			chomp $ip;
			
			if ( $ip eq "" ) {
				print "Can't resolve $domain!\n";
			} else {
				print "Domain: $domain ($domains{$domain}) -> $ip\n";
			}
		}
	}
}

sub get_ip_from_domain {
	my $domain = shift;
	my @ips;
	#print "\t$domain:\n" if $verbose;
	
	my @result = `dig $domain`;
	#print "@result\n";
	while ( my $line = shift @result ) {
		#chomp $line;
		#print "\t$line\n" if $verbose;
		if ( $line =~ /ANSWER/) {
			until ( $line =~ /AUTHORITY/ ) {
				$line = shift @result;
				chomp $line;
				#print "\t$line\n" if $verbose;

				my (@components) = split "[ \t]+", $line;
				#print "\t$#components: ", join ("/", @components) ."\n" if $verbose;
				if ( $#components == 4) {
					my ($url, $num, $in, $type, $target) = @components;
					if ( $type eq "CNAME") {
						push @ips, "$domain is CNAME pointing to $target";
					}
					if ( $type eq "A") {
						push @ips, "A $target";
					}
				}
			}
		}
	}
	
	my $ips = join ", ", @ips;
	return $ips;
}