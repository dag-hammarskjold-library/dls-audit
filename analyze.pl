#!/usr/bin/perl

use strict;
use warnings;
use feature qw|say|;
use lib '../modules';

#package Class;
#use Alpha;

#package Child;
#use Alpha;
#use parent -norequire, 'Class';

package main;
use Data::Dumper;
$Data::Dumper::Indent = 1;
use Getopt::Std;
use MARC;
use List::Util qw|any|;

INIT {}

RUN: {
	MAIN(options());
}

sub options {
	my @opts = (
		['h' => 'help'],
		['i:' => 'input file (path)'],
		#['o:' => 'output file (path)'],
		#['e:'],
	);
	getopts (join('',map {$_->[0]} @opts), \my %opts);
	if (! %opts || $opts{h}) {
		say join ' - ', @$_ for @opts;
		exit; 
	}
	$opts{$_} || die "required opt $_ missing\n" for qw||;
	-e $opts{$_} || die qq|"$opts{$_}" is an invalid path\n| for qw||;
	return \%opts;
}

sub MAIN {
	my $opts = shift;
	
	# write a list of bib#s for records that need to be added/replaced in DLS
	
	open my $update,'>','to_update.tsv';
	open my $files,'>','add_files.tsv';
	open my $missing,'>','missing.tsv';
	open my $delete,'>','to_delete.tsv';
	
	#goto HZN;
	
	open my $in,'<',$opts->{i};
	my @not_in_dls;
	while (my $line = <$in>) {
		chomp $line;
		my ($bib,$dls_id,$symbol,$hzn_dt,$dls_dt,$hzn_langs,$dls_langs) = split "\t", $line;
		
		push @not_in_dls, $bib and next if ! $dls_id;
		
		$_ ||= 0 for $hzn_dt,$dls_dt;
		say {$update} $line and next if $hzn_dt > $dls_dt;
		
		say {$delete} $line and next if ! $bib;
		
		my $comp = sub {
			my $str = shift; 
			return grep {/^[A-Z]+$/} split ';', $str;
		};
		say {$files} $line if $comp->($hzn_langs) > $comp->($dls_langs);
	}
	
	
	
	HZN:
	use Get::Hzn;
	while (@not_in_dls) {
		my @bibs = splice @not_in_dls,0,1000;
		my $bibs = join ',', @bibs;
		Get::Hzn::Dump::Bib->new->iterate (
			criteria => "select bib# from bib_control where bib# in ($bibs)",
			callback => sub {
				my $record = shift;
				return unless is_exportable($record);
				say {$missing} $record->id;
			}
		);
	}	
}

sub is_exportable {
	my $r = shift;
	return 0 if $r->record_status eq 'd';
	return 1 if $r->has_tag('191') 
		|| $r->has_tag('791') 
		|| any {$_ eq 'DHU'} $r->get_values('099','b');
	return 0;
}

END {}

__DATA__