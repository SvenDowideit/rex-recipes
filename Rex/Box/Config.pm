package Rex::Box::Config;

=pod

=head1 NAME

Rex::Box::Config - ~/.rex/config.yml 

=head1 SYNOPSIS

use Rex::Box::Config;
my $templateImageDir = Box::Config::get(qw/hosts myhost TemplateImageDir/);

=head1 DESCRIPTION

The author was too lazy to write a description.

=head1 METHODS

=cut

use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';

use Rex -base;
use Rex::Commands::Virtualization;
use Data::Dumper;


=pod

=head2 import

load the ~/.rex/config.yml if it exists

defines groups, sets the virtualisation type, and tells Rex::Box about known vm image templates


=cut

our $cfg;

sub import {
	my $class = shift;

    unless (defined($cfg)) {
		
		#TODO: move the cfg code out into a 'task module cfg / persistence module'
		#tasks need to register what options they need so that we can test and die before we start running them
		use YAML qw(LoadFile);
		$cfg = YAML::LoadFile('/home/sven/.rex/config.yml');# if (-f '~/.rex/config.yml');

		#print "\n= Loaded ==========\n".Dumper($cfg)."\n===========\n";

		map {
		#print STDERR $_;
		group $_, $cfg->{groups}->{$_}->{hosts} 
		} keys (%{$cfg->{groups}});

		set virtualization => $cfg->{virtualization};
	}
	# Do something here

	return 1;
}

=pod

=head2 get

get a setting from the config file.

my $templateImageDir = Box::Config::get(qw/hosts myhost TemplateImageDir/);

returns undef if the path is not found.

=cut

sub get {
		my $class = shift;
		my @path = @_;

		my $ref = $cfg;
		foreach (@path) {
			return unless (defined($ref));
			$ref = $ref->{$_};
		}
		return $ref;
}


1;

=pod

=head1 SUPPORT

Email me

=head1 AUTHOR

Copyright 2012 Sven Dowideit <SvenDowideit@fosiki.com>.

=cut
