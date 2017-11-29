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

INIT {}

use constant LANG_ISO_STR => {
	# unicode normalization form C (NFC)
	AR => 'العربية',
	ZH => '中文',
	EN => 'English',
	FR => 'Français',
	RU => 'Русский',
	ES => 'Español',
	DE => 'Deutsch',
};

RUN: {
	MAIN(options());
}

sub options {
	my @opts = (
		['h' => 'help'],
		['i:' => 'input file (path)'],
		['o:' => 'output file'],
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
	
	use MARC;
	
	open my $out,'>',$opts->{o};
	
	open my $fh,'<',$opts->{i};
	while (<$fh>) {
		chomp;
		my @row = split "\t";
		my $id = $row[1];
		
		my $record = MARC::Record->new;
		$record->add_field(MARC::Field->new(tag => '001', text => $id));
		$record->add_field(MARC::Field->new(tag => '980')->set_sub('c','DELETED'));
		
		print {$out} $record->to_xml;
	}
}

END {}

__DATA__