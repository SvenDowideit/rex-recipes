#
# AUTHOR: Sven Dowideit <SvenDowideit@fosiki.com>
# REQUIRES:
# LICENSE: Apache License 2.0
#
# manage base boxes for creating new vm's

#TODO: it might be better for each base box to have its own config file - so they can just be rsynced
#vagrant-bootstrap: steal everything from https://github.com/garethr/vagrantboxes-heroku/blob/master/www/index.html

package Rex::Box::Base;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';

use Rex -base;
use Rex::Config;
use Rex::Task;
use Rex::Logger;
use Rex::Commands::Fs;
use Rex::Commands::Download;
use Rex::Box::Config;

use File::Path qw(make_path);
use File::Spec;
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
    }
    else {
        print "no base boxes defined yet\n";
        add();
    }
};

=pod

=head2 Box:add

add a new template basebox to use to create new vm's

rex Box:Base:add --name=test --image=~/Downloads/basebox.img.gz

rex Box:Base:add --name=test --image=http://rex.linux-files.org/test/vm/basebox.img.gz

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
    unless ( keys(%$params) && $params->{name} ) {
        Rex::Logger::info <<"HERE";
Add or edit a Base Box to be used to create new boxes 
   rex Box:Base:add
   --name= basebox name
   --image= local file or remote (URL) source for the image or box definition
   --imagefile= name of actual diskimage file (might be inside the image archive, will be filled in by Box:Base)
   --user= --password= authentication details for admin user if using --auth=pass_auth
   --ssh= path to ssh key to use if auth_???
   --auth= auth_pass or auth_???
   
   NOTE that at the moment, we use vnc to initialise the vm, so need the root user and password (sudo isn't done yet)
HERE
        exit;
    }

    my $templateImageDir = getTemplateImageDir( undef, $params->{name} );

    #TODO: make_path nees to be in Rex::Commands::Fs
    make_path($templateImageDir);

    my ( $imageFile, $imagePath );
    if (   !Rex::Box::Config->getCfg( @path, 'imagefile' )
        && !exists( $params->{image} )
        && Rex::Box::Config->getCfg( @path, 'image' ) )
    {

        #lets try again
        $params->{image} = Rex::Box::Config->getCfg( @path, 'image' );
    }
    if ( $params->{image} ) {
        my $new_image = $params->{image};
        $new_image =~ s/~/Rex::Config->_home_dir()/e;

        my ( $volume, $directories );
        ( $volume, $directories, $imageFile ) =
          File::Spec->splitpath($new_image);
        $imagePath = File::Spec->catfile( $templateImageDir, $imageFile );

        if ( is_file($new_image) ) {
            Rex::Logger::info("copying $new_image to $imagePath");
            cp( $new_image, $imagePath );
        }
        else {

            #TODO: really would be better to test for updates..
            unless ( -e $imagePath ) {
                Rex::Logger::info("downloading $new_image to $imagePath");

                #is is a URL or scp or?
                download( $new_image, $imagePath );
            }
            else {
                Rex::Logger::info("using $imagePath");
            }
        }
    }

    #TODO: what about more than one disk file?
    if ( $imagePath && -e $imagePath ) {
        if (   $imagePath =~ /box$/
            && !exists( $params->{user} )
            && !exists( $params->{password} ) )
        {
            $params->{user}     = 'root';
            $params->{password} = 'vagrant';
        }
        Rex::Logger::info("extracting $imageFile");

        #TODO: i'd like it to leave the original .gz file..
        extract( $imagePath, to => $templateImageDir );

        #TODO: no idea what to do with sub-dirs..
        my @files = ls($templateImageDir);
        foreach my $file (@files) {
            my $filePath = File::Spec->catfile( $templateImageDir, $file );
            next unless -f $filePath;
            print $filePath. "\n";

            #looks like i can't actually use cluster size
            if ( $file =~ /(vdi|vmdk)$/ ) {
                $params->{imagefile} = $file;
                last;
            }

            #use qemu-img info to test if its an image it knows
            #TODO: see LibVirt::create for QEMU-IMG stuff that needs extraction
            my $result = `qemu-img info $filePath`;
            Rex::Logger::info($result);
            if ( $result =~ /cluster_size/ ) {

                #I'm guessing this is an indicator of a disk img
                $params->{imagefile} = $file;
                last;
            }
        }
    }

    my @path = ( qw/Base TemplateImages/, $params->{name} );

    #Rex::Logger::info("found keys: ".join(', ', keys(%$params)));
    foreach my $key ( keys(%$params) ) {
        next if ( $key eq 'name' );
        Rex::Box::Config->setCfg( @path, $key, $params->{$key} );
    }

    Rex::Box::Config->save();

};

=pod

=head2 Box:exists

see if the base box is defiend locally, or on the hoster

make sure there is a template imagefile ready for use, and that we know the box's user&password

so lots of rsyncing around

=cut

desc
  "do whatever it takes to make the base box exist where the hoster needs it.";
task "exists", sub {
    my $params = shift;
    unless ( $params->{base_box_name} ) {
        Rex::Logger::info <<"HERE";
initialise a Base Box to be used to create new boxes 
   rex Box:Base:exists
   --base_box_name= basebox name
HERE
        exit;
    }
    my $base_box = Rex::Box::Config->getCfg( qw/Base TemplateImages/,
        $params->{base_box_name} );
    unless ($base_box) {
        Rex::Logger::info <<"HERE";
$params->{base_box_name} not defined on this host.
#TODO: look on hoster..
#TODO: look on the net..
HERE
        exit;
    }

    my $templateImageDir =
      getTemplateImageDir( undef, $params->{base_box_name} );

    my $hosterTemplateFile =
      File::Spec->catfile( $templateImageDir, $base_box->{imagefile} );
    unless ( is_file($hosterTemplateFile) ) {

        #look locally, or URL, build and send over..
    }

    #TODO: conversions..

    #Rex::Box::Config->setCfg(@path, $key, $params->{$key});

    #Rex::Box::Config->save();

};

=pod

=head2 getBase

get a basebox to use

my $templateImageDir = Box::Base->get('debianbox');

returns undef if the box is not found.


=cut

sub getBase {
    my $class   = shift;
    my $boxname = shift;

    my $base = Rex::Box::Config->getCfg( qw/Base TemplateImages/, $boxname );
    return $base;
}

sub getTemplateImageDir {
    my $server = shift || Rex::get_current_connection()->{server};
    my $templateImageDir =
      Rex::Box::Config->getCfg( 'hosts', $server, 'TemplateImageDir' )
      || '~/.rex/Base';
    $templateImageDir =~ s/~/Rex::Config->_home_dir()/e;
    shift unless defined( $_[0] );
    return File::Spec->catdir( $templateImageDir, @_ );
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

