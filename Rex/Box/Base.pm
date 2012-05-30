#
# AUTHOR: Sven Dowideit <SvenDowideit@fosiki.com>
# REQUIRES: 
# LICENSE: Apache License 2.0
# 
# manage base boxes for creating new vm's

#TODO: it might be better for each base box to have its own config file - so they can just be rsynced

package Rex::Box::Base;


use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';


use Rex -base;
use Rex::Config;
use Rex::Task;
use Rex::Logger;
use Rex::Box::Config;

use YAML;

=pod

=head2 Box:list

list all the available baseboxes

=cut

desc "list base boxes";
task "list", sub {
	my $base = Rex::Box::Config->getCfg(qw/Base TemplateImages/);
	if ($base) {
        print YAML::Dump $base;
	} else {
		print "no base boxes defined yet\n";
		add();
	}
};

=pod

=head2 Box:add

add a new template basebox to use to create new vm's

should support as many formats as possible, and convert to what you need.

creates the following info to ~/.rex/config.yml:

Base:
  DefaultBox: debianbox
  TemplateImages: 
    debianbox:
      image: debianbox.img
      url: http://localhost/somewhere/debianbox.img
      user: root
      password: rex
      auth: pass_auth

=cut

desc "add a new base box";
task "add", sub {
	my $params = shift;
	unless (keys(%$params) && $params->{name}) {
		Rex::Logger::info <<"HERE";
Add or edit a Base Box to be used to create new boxes 
   rex Box:Base:add
   --name= basebox name
   --image= local file or remote (URL) source for the image or box definition
   --imagefile= name of actual diskimage file (only needed if Box:Base gets confused)
   --user= --password= authentication details for admin user if using --auth=pass_auth
   --ssh= path to ssh key to use if auth_???
   --auth= auth_pass or auth_???
   
   NOTE that at the moment, we use vnc to initialise the vm, so need the root user and password (sudo isn't done yet)
HERE
		exit;
	}
	my @path = (qw/Base TemplateImages/, $params->{name});
	
	#Rex::Logger::info("found keys: ".join(', ', keys(%$params)));
	foreach my $key (keys(%$params)) {
			next if ($key eq 'name');
			Rex::Box::Config->setCfg(@path, $key, $params->{$key});
	}
	
	Rex::Box::Config->save();    

};


=pod

=head2 getBase

get a basebox to use

my $templateImageDir = Box::Base->get('debianbox');

returns undef if the box is not found.


=cut

sub getBase {
	my $class = shift;
	my $boxname = shift;
	
	my $base = Rex::Box::Config->getCfg(qw/Base TemplateImages/, $boxname);
	return $base;
}

1;

=pod

=head2 Box Module

quickly manage virtual machine configurations and deployments

=head2 USAGE

 rex -H $host Box:Base:add --name=debian --image=http://rex.linux-files.org/test/vm/basebox.img.gz --user=root --password=test

Or, to use it from a project's Rexfile

 use Rex::Box::Base;
    
 task "add", sub {
    Box::create({
       name => "baz"
    });
 };

=head1 SUPPORT

email Sven Dowideit <SvenDowideit@fosiki.com>

=head1 AUTHOR

Copyright 2012 Sven Dowideit <SvenDowideit@fosiki.com>

