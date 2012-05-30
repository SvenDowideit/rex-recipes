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
use Rex::Config;
use Rex::Args;

use File::Path qw(make_path);
use YAML qw(LoadFile DumpFile);

=pod

=head2 import

load the ~/.rex/config.yml if it exists

defines groups, sets the virtualisation type, and tells Rex::Box about known vm image templates

#TODO: consider a server wide cfg at /etc/rex, or in the cpan module cfg area

=cut

our $cfg;
use constant cfgDir => '~/.rex';
use constant cfgFile => 'config.yml';

=pod

=head2 Box:list

list all the available baseboxes

=cut

desc "list config";
task "list", sub {
	my $base = Rex::Box::Config->getCfg();
	print YAML::Dump $base;
};


sub import {
	my $class = shift;


    if (!defined($cfg)) {
			my $configFile = cfgDir.'/'.cfgFile;
			$configFile =~ s/~/Rex::Config->_home_dir()/e;

		if (-e $configFile) {
				
				#TODO: move the cfg code out into a 'task module cfg / persistence module'
				#tasks need to register what options they need so that we can test and die before we start running them
				$cfg = YAML::LoadFile($configFile);

				#print "\n= Loaded ==========\n".YAML::Dump($cfg)."\n===========\n";

				map {
						my $hosts = Rex::Box::Config->get('groups', $_, 'hosts') ;
						#TODO: need to support lists..., and lists on cmdline (csv?)
						group $_, $hosts if ($hosts ne '1');
						
				} keys (%{$cfg->{groups}});

				set virtualization => $cfg->{virtualization};
			} else {
				Rex::Logger::info("no ".cfgDir.'/'.cfgFile." file found, using defaults (localhost)");
				Rex::Logger::info("  see Box:config task to set basic values of ".cfgDir.'/'.cfgFile);
				$cfg = {};
			}
	}

	return 1;
}


=pod

=head2 get

get a setting from the cmdline parameters or default to the config file.

my $templateImageDir = Box::Config->get(qw/hosts myhost TemplateImageDir/);

returns undef if the path is not found.


=cut

sub get {
		my $class = shift;
		die 'here' unless $class eq 'Rex::Box::Config';
		my @path = @_;
		
		#TODO: consider shortcut maps of cfg's specified by the task module
		my $paramname = join(':', @path);
		my %params = Rex::Args->get();
		
		my $val = $params{$paramname};
		return $val if (defined($val));
		
		#TODO: if there's only one element in @path, and if it has :'s, split it..
		return Rex::Box::Config->getCfg(@path);
}


=pod

=head2 getCfg

get a setting from the config file.

my $templateImageDir = Box::Config->getCfg(qw/hosts myhost TemplateImageDir/);

returns undef if the path is not found.

It'd be nice if there was a get() that also took values from $params, to over-ride the conf..
(this would need to be a separate api tho)

=cut

sub getCfg {
		my $class = shift;
		my @path = @_;

		my $ref = $cfg;
		foreach (@path) {
			last if (!defined($ref));
			$ref = $ref->{$_};
		}
		return $ref;
}

=pod

=head2 setCfg

set a setting from the config file.

Box::Config->setCfg(qw/hosts myhost TemplateImageDir/, '~/.rex/Box/Templates');

or the 2 param version:

Box::Config->setCfg(hosts:myhost:TemplateImageDir, '~/.rex/Box/Templates');



=cut

sub setCfg {
		my $class = shift;
		my @path = @_;
		my $value = pop @path;
		my $key = pop @path;
		if ($key =~ /:/) {
			@path = split(/:/, $key);
			$key = pop @path;
		}
		Rex::Logger::info("set ".join(':', @path).":$key to ($value)");

		my $ref = $cfg;
		foreach (@path) {
			$ref->{$_} = {} unless (exists $ref->{$_});
			$ref = $ref->{$_}
		}
		$ref->{$key} = $value;
}


=pod

=head2 save

set a setting from the config file.

my $templateImageDir = Box::Config->setCfg(qw/hosts myhost TemplateImageDir/, '~/.rex/Box/Templates');


=cut

sub save {
	my $class = shift;
	return if (!defined $cfg);
	my $configDir = cfgDir;
	$configDir =~ s/~/Rex::Config->_home_dir()/e;
	make_path($configDir);
	YAML::DumpFile($configDir.'/'.cfgFile, $cfg);
}

1;

=pod

=head1 SUPPORT

Email Sven Dowideit <SvenDowideit@fosiki.com>.

=head1 AUTHOR

Copyright 2012 Sven Dowideit <SvenDowideit@fosiki.com>.

=cut
