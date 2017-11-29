#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw|say|;
use FindBin;
use lib "$FindBin::Bin/../modules";

package DLS::Data;
use Alpha;
use Data::Dumper;

has 'file' => (
	is => 'rw',
	param => 0
);

has 'map', is => 'ro';
has 'symbols', is => 'ro';
has 'files', is => 'ro';
has 'created', is => 'ro';
has 'changed', is => 'ro';

sub load_data {
	my $self = shift;
	
	open my $fh,'<',$self->file;
	
	say 'loading dls data...';
	my $next = <$fh>;
	FILE: while (<$fh>) {
		chomp;
		my @row = split "\t", $_;
		my ($dls_id,$ctrl,$symbol,$urls,$created,$changed) = @row;
		next unless $created; # indicates record orginated in hzn
		my $bib;
		MAP: {
			if ($ctrl =~ /\(DHL\)([^\s]+)/) {
				$bib = $1;
				$self->{map}->{$bib} = $dls_id;
			} elsif ($ctrl =~ /AUTH/) {
				next FILE;
			} else {
				#die "DHL ID not found for DLS record $dls_id"; 
			}
			$self->{symbols}->{$bib} = $symbol if $symbol;
		}
		FILES: {
			last if index($urls, 'digitallibrary.un.org') == -1;
			my @urls = grep /digitallibrary.un.org\/record/, split /; /, $urls;
			for my $i (0..$#urls) {
				my $lang = $1 if $urls[$i] =~ /\-(AR|ZH|EN|FR|RU|ES|DE)\.pdf$/;
				#$lang || warn "no lang for $dls_id - $urls[$i]";
				$lang ||= '%'.$i;
				$self->{files}->{$dls_id}->{$lang} = $urls[$i]; #[ $sizes[$i], $urls[$i] ];
			}
		}
		AUDIT: {
			$self->{created}->{$bib} = $created;
			$self->{changed}->{$bib} = $changed if $changed;
			$self->{changed}->{$bib} ||= $created;
		}
	}
	return $self;
}

package Audit::Data;
use Alpha;
use Data::Dumper;
use Get::Hzn;
use Utils qw|date_hzn_8601|;

has 'created', is => 'ro';
has 'changed', is => 'ro';

sub load_data {
	my $self = shift;
	say "loading hzn audit data";
	my $sql = <<'	#';
	select 
		bib#, 
		create_date, 
		create_time,
		change_date,
		change_time
	from 
		bib_control
	#
	Get::Hzn->new->sql($sql)->execute (
		callback => sub {
			my $row = shift;
			my $bib = $row->[0];
			$self->{created}->{$bib} = date_hzn_8601($row->[1],$row->[2]);
			$self->{changed}->{$bib} = date_hzn_8601($row->[3],$row->[4]) if $row->[3];
			$self->{changed}->{$bib} ||= $self->{created}->{$bib};
		}
	);
	return $self;
}

package main;
use Data::Dumper;
$Data::Dumper::Indent = 1;
use Getopt::Std;
use List::Util qw/any/;
use Get::Hzn;

INIT {}

use constant LANG => {
	العربية => 'AR',
	中文 => 'ZH',
	Eng => 'EN',
	English => 'EN',
	Français => 'FR',
	Русский => 'RU',
	Español => 'ES',
	Other => 'DE'
};

RUN: {
	MAIN(options());
}

sub options {
	my @opts = (
		['h' => 'help'],
		['i:' => 'dls export file'],
		['o:' => 'output file'],
		['s:' => 'sql'],
		['3:' => 's3 db']
	);
	getopts (join('',map {$_->[0]} @opts), \my %opts);
	if (! %opts || $opts{h}) {
		say join ' - ', @$_ for @opts;
		exit; 
	}
	$opts{$_} || die "required opt $_ missing\n" for qw|i o s|;
	-e $opts{$_} || die qq|"$opts{$_}" is an invalid path\n| for qw|i|;
	return \%opts;
}

sub MAIN {
	my $opts = shift;
	
	# load dls and bib_control data
	
	my $hzn = Audit::Data->new->load_data;
	my $dls = DLS::Data->new(file => $opts->{i})->load_data;
	
	use DBI;
	my $dbh = DBI->connect('dbi:SQLite:dbname='.$opts->{3},'','');
	# scan horizon, look up loaded data, write to hzn and dls to file
	
	say "writing report...";
	
	my @header = qw {
		HZN_ID
		DLS_ID
		SYMBOL
		HZN_LAST_CHANGED
		DLS_LAST_CHANGED
		HZN_FILES
		DLS_FILES
	};
	
	open my $out,'>',$opts->{o};
	my @ids = Get::Hzn->new(sql => $opts->{s})->execute;
	say scalar @ids;
	
	while (@ids) {
		my %row;
		my $row = shift @ids;
		my $bib = $row->[0];
		$row{HZN_ID} = $bib;
		IN_DLS: {
			if (my $dls_id = $dls->map->{$bib}) {
				$row{DLS_ID} = $dls_id;
			} else {
				goto WRITE;
			}
		}
		SYMBOL: {
			my $sym = $dls->{symbols}->{$bib};
			$row{SYMBOL} = $sym if $sym;
		}
		UP_TO_DATE: {
			$row{HZN_LAST_CHANGED} = $hzn->changed->{$bib};
			$row{DLS_LAST_CHANGED} = $dls->changed->{$bib};
		}
		FILES: {
			#last unless $record->has_tag('191');
			my $langs = $dbh->selectall_arrayref("select lang from docs where bib = $bib");
			my @hzns;
			for (@$langs) {
				my $lang = $_->[0];
				#push @hzns, LANG->{$lang} if LANG->{$lang};
				push @hzns, $lang;
			}
			$row{HZN_FILES} = join ';', sort @hzns;
			if (my $fields = $dls->files->{$dls->map->{$bib}}) {
				$row{DLS_FILES} = join ';', sort keys %$fields;
			}
		}
		WRITE: {
			my @row;
			for (@header) {
				my $val = $row{$_};
				$val ||= '';
				push @row, $val;
			}
			say $out join "\t", @row;
		}
		
		delete $dls->{map}->{$bib};
	}
	
	my $left = $dls->{map};
	for (keys %$left) {
		say {$out} "\t".$left->{$_};
	}
}

END {}

__DATA__