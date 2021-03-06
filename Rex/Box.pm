#
# AUTHOR: Sven Dowideit <SvenDowideit@fosiki.com>
# REQUIRES:
# LICENSE: Apache License 2.0
#
# generalised vm box deployment to libvirt

package Rex::Box;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.02';

use Rex -base;
use Rex::Config;
use Rex::Group;
use Rex::Batch;
use Rex::Task;
use Rex::Cache;
use Rex::Logger;
use Rex::Output;
use Rex::Commands::Virtualization;
use Rex::Commands::Fs;
use Rex::Box::Config;
use Rex::Box::Base;

use File::Spec;
use YAML;

#TODO: extract this so it only gets used if needed, and installed.
use Net::VNC;

#TODO: its probably better to have the task module or tasks register that they need certain cfg's
#and to allow them to be set from the cmdline..
#init groups needed when there's no config.yml
use Rex::Group;
unless ( Rex::Group->is_group('hoster') ) {
    group 'hoster', '<local>';
}

#TODO: hardcoding libvirt - can we try to detect what if anything is installed and use it?
set virtualization => 'LibVirt';

=pod

=head2 Rex::Box->configurewith(task)

configure the new host with the specified task

=cut

sub configurewith {
    my $self     = shift;
    my $taskname = shift;

    Rex::TaskList->modify( 'before', $taskname, \&runbefore, 'main',
        'Rex/Box.pm', 666 );
}

sub runbefore {
    my ( $server, $server_ref, $params ) = @_;

#TODO: this presumes that <local> can talk directly to the vm - which might also not be true.
    if (   !exists $params->{name}
        || !defined $params->{name}
        || $params->{name} eq '1' )
    {
        if ( $params->{name} && $params->{name} eq '1' ) {
            Rex::Logger::info
              "--name=$params->{name} ambiguous, please use another name";
        }
        else {
            Rex::Logger::info 'need to define a --name= param';
        }
        my ( $package, $file, $line ) = caller;
        print STDERR "called by $package, $file, $line\n";
        exit;
    }

    #base_box settings (needed to get the vm's user&pass)
    my $base_name = $params->{base}
      || Rex::Box::Config->get(qw(Base DefaultBox));
    die
"need to select a base image to create the vm from (either  --base= or set the Base:DefaultBox setting using Box:config)"
      unless ($base_name);
###Box::Base::exists(\{%params, base=>$base_name});  #make sure the basebox is ready to go locally
    my $base_box = Rex::Box::Base->getBase($base_name);
    die
      "sorry, base box '$base_name' is not configured yet - see Box:Base:config"
      unless ($base_box);

    Rex::Logger::info( 'running before create on ' . run 'uname -a' );

    group 'vm', $params->{name};

    my $cfg = Rex::Box::Config->getCfg();

#make sure the vm exists, or create it
#Rex::TaskList->get_task("Box:exists")->run($cfg->{virtualization_host}, params => $params);
    do_task 'Box:exists';

    #exists(%$params);

    my $vmtask = Rex::TaskList->get_task("create");

#TODO: need to add this info to the destination server's cfg, so the box can later be deleted.

    $vmtask->set_user( $base_box->{user} );
    $vmtask->set_password( $base_box->{password} );

    ##CAN"T CALL THIS IN BEFORE()    $vmtask->set_server($params->{name});

    $$server_ref = $params->{name};

    pass_auth()
      ; #TODO: it bothers me that pass_auth works different from user() and password()
}

=pod

=head2 Box:exists

used to ensure a host exists before the rexfile configures it

=cut

desc "exists";
task "exists", sub {
    my ($params) = @_;

#this shim allows us to put code around the create task - as need(exists) does not call the before/after/around wrappers (need to explain why)
#Rex::Task->run("Box:create", undef, $params);
    do_task 'Box:create';

};

=pod

=head2 Box:create

lists the virtual machines in the RexConfig hoster group

=cut

desc "create";
task "create",
  group => "hoster",
  sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    die "--name=$params->{name} ambiguous, please use another name"
      if ( $params->{name} eq '1' );

    Rex::Logger::info( 'running Box:create on ' . run 'uname -a' );

#refuse to create if the host already exists - test not only libvirsh, but dns etc too (add a --force..)
#    my $host = do_task("Box:status");  #BUG? this do_task returns nothing :() - should work as we're on the same host, so could use the same forked process... else  IPC
    my $host = _status( $params->{name} );

    #base_box settings
    my $base_name = $params->{base}
      || Rex::Box::Config->get(qw(Base DefaultBox));
    my $base_box = Rex::Box::Base->getBase($base_name);

    if ( defined($host) ) {
        print 'info' . Dump $host;

#TODO: can't do this - without IPC, the initial task doesn't know about the die, so continues on
#die "$params->{name} already exists - you can --force it if you need\n" unless ($params->{force});
        print "using exiting host: $params->{name}\n";
        vm start => $params->{name} unless ( $host->{status} eq 'running' );
    }
    else {

        #vm hosting server settings
        my $server = Rex::get_current_connection()->{server};
        my $imageDir = Rex::Box::Config->getCfg( 'hosts', $server, 'ImageDir' );
        die
"hosts:$server:ImageDir not set yet - need to know where to put the new vm's disk image"
          unless $imageDir;

        #libvirsh can create but can't start a vm that uses ~/
        $imageDir =~ s/~/Rex::Config->_home_dir()/e;

        my %vmCfg = (
            network => [
                {
                    type   => "bridge",
                    bridge => "br100",
                },
            ],
            storage  => [ {}, ],
            graphics => {
                type     => 'vnc',
                port     => '-1',
                autoport => 'yes',
                listen   => '*'
            }
        );

        die
"need to select a base image to create the vm from (either  --base= or set the Base:DefaultBox setting using Box:config)"
          unless ($base_name);
        if ( $base_name =~ /\.iso/i ) {

            #die "$base_name does not exist" unless (-f $base_name);

         #use an iso
         #TODO: I wonder if we can store the basebox name used to create this vm
         #this is the virtio disk - not very useful for win2008 etc
            $vmCfg{storage}[0] = {
                file =>
                  File::Spec->catfile( $imageDir, $params->{name} . ".img" ),
                size => '10G'
            };
            #so using ide instead
            $vmCfg{storage}[0] = { 
                size => '10G',
               bus=> 'ide',
                file => File::Spec->catfile( $imageDir, $params->{name} . ".img" ), 
                dev => 'hda', 
              address=>{
                type       => "drive",
               controller => 0,
               bus        => 0,
               unit       => 0, 
            }};

            #make sure the ISO is on the remote server
            my $localISO = $base_name;
            $localISO =~ s/~/Rex::Config->_home_dir()/e;
            my ( $volume, $directories, $imageFile ) =
              File::Spec->splitpath($localISO);
            my $templateImageDir =
              Rex::Box::Base::getTemplateImageDir( undef, 'ISOs' );
            my $ISO = File::Spec->catfile( $templateImageDir, $imageFile );
            if ( !is_file($ISO) ) {
                print "uploading $ISO from $localISO\n";

                #TODO: should probly move this to Box::Base
                mkdir($templateImageDir) unless is_dir($templateImageDir);

                file $ISO, source => $localISO;
            }

            $vmCfg{storage}[1] = { file => $ISO, dev=> 'hdc'};
            $vmCfg{boot} = 'cdrom';

#if this is a windows iso, we'll need a VirtIO driver disk from http://alt.fedoraproject.org/pub/alt/virtio-win/latest/images/bin/
#TODO: need to bump up the device - else the cfg has 2 cdroms at hdc (and bad ide values)
            my $virtISO = File::Spec->catfile( $templateImageDir, 'virtio-win-0.1-30.iso' );
            $vmCfg{storage}[2] = { file => $virtISO, dev => 'hdd', address=>{
                type       => "drive",
               controller => 0,
               bus        => 1,
               unit       => 1, 
            }};

        }
        else {

            #use a Base Box
            Rex::Box::Base::exists( { %$params, base_box_name => $base_name } )
              ; #make sure we have an image, in the right format for this host, and in the right locations..
            die
"sorry, base box '$base_name' is not configured yet - see Box:Base:config"
              unless ($base_box);

            my $templateImageDir =
              Rex::Box::Base::getTemplateImageDir( undef, $params->{base} );
            die
"hosts:$server:TemplateImageDir not set yet - need to know where to put the new vm's disk image"
              unless $templateImageDir;

          #TODO: need to test for, download and possibly convert basebox image..

            #make sure the template file (and dir) is on the remote host.
            my $template =
              File::Spec->catfile( $templateImageDir, $base_box->{imagefile} );
            print
"Creating vm named: $params->{name} on $server from $base_name using $template\n";
            unless ( is_file($template) ) {
                my $localTemplateImageDir =
                  Rex::Box::Base::getTemplateImageDir( '<local>',
                    $params->{base} );
                my $localtemplate =
                  File::Spec->catfile( $localTemplateImageDir,
                    $base_box->{imagefile} );

                print "uploading template from $localtemplate\n";

                #TODO: should probly move this to Box::Base
                mkdir($templateImageDir) unless is_dir($templateImageDir);

                file $template, source => $localtemplate;
            }

         #TODO: I wonder if we can store the basebox name used to create this vm
            $vmCfg{storage}[0] = {
                file =>
                  File::Spec->catfile( $imageDir, $params->{name} . ".img" ),
                template => $template,
            };
        }

        #TODO: refuse to name a vm with chars you can't use in a hostname
        print "creating.....\n";
        vm create => $params->{name}, %vmCfg;
        print "Starting vm named: $params->{name} \n";

        vm start => $params->{name};

    }

    #I'd like to move this into an 'after Box:exists but something goes wrong.
    #TODO: and now test for name->ip->mac address..
    #TODO: and test that the ping succeeds - it might need starting!
    my $ping = run "ping -c1 $params->{name}";
    $ping =~ /\((.*?)\)/;
    my $ping_ip = $1;

    unless ( defined($base_box) ) {
        my $vnc = vm vncdisplay => $params->{name};

        print "-- insufficient info to do more setup (try vnc: $vnc)\n";
        return;
    }

    my $ips;
    my $count = 0;
    while ( !defined($ips) || !defined( $$ips[0] ) ) {
        __use_vnc( $params->{name}, $base_box->{user}, $base_box->{password} )
          if ( $count > 0 )
          ;    #kick the server with vnc if we don't get instant success'
        print "   try\n";
        $ips = __vm_getip( $params->{name} );
        sleep(1);
        $count++;
    }

#TODO: terrible assumption - how to deal with more than one network interface per host?
    print "IP: --$$ips[0]--\n";
    if ( defined($ping_ip) && ( $$ips[0] eq $ping_ip ) ) {
        print
"hostname already mapped to IP, and mac - flying by the seat of our pants\n";
    }

  VMTASK: {
        print "Setting user to " . $base_box->{user} . "\n";

#TODO: I wish this was not in the Rexfile, as imo its part of the VM only creation..
#but, to run it, we need the vm's user details..
#OH. those are also vm details..
        my $vmtask = Rex::TaskList->get_task("Box:set_hostname");
        $vmtask->set_user( $base_box->{user} );
        $vmtask->set_password( $base_box->{password} );
        pass_auth()
          ; #TODO: it bothers me that pass_auth works different from user() and password()
            # if ($base_box->{auth} eq 'pass_auth');
        $vmtask->set_server( $$ips[0] );

        $vmtask->run( $$ips[0], params => $params );
    }
  };

=pod

=head2 Box:list

lists the virtual machines in the RexConfig hoster group

=cut

desc "lists the virtual machines in the RexConfig hoster group";
task "list",
  group => "hoster",
  sub {
    print Dump vm list => "all";
  };

desc "start --name=";
task "start",
  group => "hoster",
  "name", sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print "Starting vm named: $params->{name} \n";
    print Dump vm start => $params->{name};
  };
desc "stop --name=";
task "stop",
  group => "hoster",
  "name", sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print "Stoping vm named: $params->{name} \n";
    print Dump vm shutdown => $params->{name};
  };

desc "status --name=";
task "status",
  group => "hoster",
  sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    return _status( $params->{name} );
  };

#extracted because using $host = needs('Box:status', $params) does not work
sub _status {
    my $hostname = shift;

    my $list = vm list => "all";
    foreach my $test (@$list) {
        if ( $test->{name} eq $hostname ) {
            Rex::Logger::info( Dump $test);

            return $test;
        }
    }
    return;
}

desc "info --name=";
task "info",
  group => "hoster",
  sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print Dump vm dumpxml => $params->{name};
  };

desc "delete --name=";
task "delete",
  group => "hoster",
  "name", sub {
    my ($params) = @_;

    my $server = Rex::get_current_connection()->{server};
    my $imgDir = Rex::Box::Config->getCfg( 'hosts', $server, 'ImageDir' );
    die "need to set hosts:$server:ImageDir in Box:config" unless $imgDir;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    my $host = _status( $params->{name} );
    unless ($host) {
        print "vm '$params->{name}' not found\n";
        return -1;
    }
    if ( $params->{stop} && !( $host->{status} eq 'shut off' ) ) {
        vm shutdown => $params->{name};
        print "stopping $params->{name} ";
        until ( $host->{status} eq 'shut off' ) {
            print '.';
            sleep(1);
            $host = _status( $params->{name} );
        }
        print "\n";
    }
    unless ( $host->{status} eq 'shut off' ) {
        print "vm '$params->{name}' not stopped (add --stop to force)\n";
        return -1;
    }

    print "Deleting vm named: $params->{name}from $server \n";
    vm delete => $params->{name};
    print "Deleting image named: $imgDir/$params->{name}.img \n";

    #rm "$imgDir/$params->{name}.img";
    #Fs::rm doesn't do an rm -f
    run "rm -f $imgDir/$params->{name}.img";

  };

desc "vnc port";
task "vnc",
  group => "hoster",
  "name", sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print "getting vnc server:port for vm named: $params->{name} \n";
    my $vnc = vm vncdisplay => $params->{name};
    my $server = Rex::get_current_connection()->{server};

    # replace * with server name
    $vnc =~ s/\*/$server/e;
    print "VNC: $vnc\n";
  };

desc "ip";
task "ip",
  group => "hoster",
  "name", sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print "getting ip for vm named: $params->{name} ... " . hostname() . " \n";

    my $ips = __vm_getip( $params->{name} );
    print "IP: " . join( ',', @$ips ) . "\n";
  };

desc 'set basic Rex::Box config file options';
task 'config', sub {
    my $params = shift;
    unless ( keys(%$params) ) {
        Rex::Logger::info <<"HERE";
Configuration options for 
   rex Box:config
   --host= to set the host where your virtual machines are running
   
   --any:colon:separated:path=value that is not listed above will also be saved into the config.yml
HERE
        exit;
    }

    #Rex::Logger::info("found keys: ".join(', ', keys(%$params)));
    foreach my $key ( keys(%$params) ) {
        Rex::Box::Config->setCfg( qw/groups hoster hosts/, $params->{host} )
          if ( $key eq 'host' );
        next if ( $key eq 'host' );
        Rex::Box::Config->setCfg( $key, $params->{$key} );
    }

    Rex::Box::Config->save();
};

sub __use_vnc {
    my $vmname   = shift;
    my $username = shift;
    my $password = shift;

    my $server = Rex::get_current_connection()->{server};
    my $vncport = vm vncdisplay => $vmname;
    $vncport =~ s/.*:(.*)/$1/;
    $vncport = 5900 + $1;
    print "---- vnc to $vmname on $username @ $server:$vncport\n";

#TODO: use the vnc console to trigger traffic between the vmserver (where arp is running) and the vm
    my $vnc = Net::VNC->new( { hostname => $server, port => $vncport } );

    #$vnc->depth(8); - don't do this.
    $vnc->login;

    #in case we need to log in?
    $vnc->send_key_event_string($username);
    $vnc->send_key_event(0xff0d);
    sleep(1);
    $vnc->send_key_event_string($password);
    $vnc->send_key_event(0xff0d);
    sleep(1);
    $vnc->send_key_event_string( 'ping -c 2 ' . $server );
    $vnc->send_key_event(0xff0d);
    sleep(1);

    #TODO: er, $vnc->close() ???

}

sub __vm_getip {
    my $vmname = shift;

    #use ping first - we might already the dns server knowing where we are..
    run "ping -c2 $vmname";

#see http://rwmj.wordpress.com/2010/10/26/tip-find-the-ip-address-of-a-virtual-machine/
    my %addrs;
    my @arp_lines = split /\n/, run 'arp -a';
    foreach (@arp_lines) {
        if (/\((.*?)\) at (.*?) /) {
            $addrs{ lc($2) } = $1;
        }
    }

    my $opt = vm dumpxml => $vmname;
    my $interfaces = $opt->{devices}->{interface};

    #i presume that if there are 2 network if's that this is a list..
    $interfaces = [$interfaces] unless ( ref($interfaces) eq 'ARRAY' );

    my @ips;
    foreach my $if ( @{$interfaces} ) {
        my $mac = lc( $if->{mac}->{address} );
        print "\t$mac => $addrs{$mac}\n" if $addrs{$mac};
        push( @ips, $addrs{$mac} );
    }
    return \@ips;
}

#This call should probably go into a Box::Host cfg module or something
use Rex::Commands::Sysctl;
use Rex::Commands::Upload;

desc "set_hostname --name=";
task "set_hostname", sub {
    my ($params) = @_;

    my $server = Rex::get_current_connection()->{server};
    Rex::Logger::info(
        "running set_hostname on $server, setting name to $params->{name}");

    Rex::Logger::info( 'running set_hostname on ' . run 'uname -a' );

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    run "echo $params->{name} > /etc/hostname ; /etc/init.d/hostname.sh";

    #CAREFUL: don't call run sysctl '' - as sysctl already has a run in it.
    my $newhost = sysctl "kernel.hostname='$params->{name}'";

#die "failed to set hostname (should be $params->{name}) is $newhost;\n" unless ($params->{name} eq $newhost);

    #get dhclient to tell the dhcp server its name too
    run
"echo send host-name \\\"$params->{name}\\\"\\\; >> /etc/dhcp/dhclient.conf ; dhclient";

    #throw the ssh key over.
    #shame that upload doesn't do dir's
    run 'mkdir .ssh ; chmod 700 .ssh';
    upload $ENV{HOME} . '/.ssh/id_rsa',     '.ssh';
    upload $ENV{HOME} . '/.ssh/id_rsa.pub', '.ssh/authorized_keys';

};

1;

=pod

=head2 Box Module

quickly manage virtual machine configurations and deployments

=head2 USAGE

 rex -H $host Box:create --name=baz

Or, to use it from a project's Rexfile

 use Rex::Box;
    
 task "create", sub {
    Box::create({
       name => "baz"
    });
 };

=head1 SUPPORT

email Sven Dowideit <SvenDowideit@fosiki.com>

=head1 AUTHOR

Copyright 2012 Sven Dowideit <SvenDowideit@fosiki.com>

