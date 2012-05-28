#
# AUTHOR: Sven Dowideit <SvenDowideit@fosiki.com>
# REQUIRES: 
# LICENSE: Apache License 2.0
# 
# generalised vm box deployment to libvirt

package Rex::Box;

use Rex -base;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';


use Rex;
use Rex::Config;
use Rex::Group;
use Rex::Batch;
use Rex::Task;
use Rex::Cache;
use Rex::Logger;
use Rex::Output;
use Rex::Commands::Virtualization;
use Rex::Commands::Fs;

use Data::Dumper;

#TODO: extract this so it only gets used if needed, and installed.
use Net::VNC;

group 'vm', 'fake';

#TODO: move the cfg code out into a 'task module cfg / persistence module'
#tasks need to register what options they need so that we cna test and die before we start running them
use YAML qw(LoadFile);
my $cfg = YAML::LoadFile('/home/sven/.rex/config.yml');# if (-f '~/.rex/config.yml');

#print "\n===========\n".Dumper(keys (%{$cfg->{groups}}))."\n===========\n";

map {
		#print STDERR $_;
		group $_, $cfg->{groups}->{$_}->{hosts} 
	} keys (%{$cfg->{groups}});

set virtualization => $cfg->{virtualization};


=pod

=head2 new

  my $object = Rex::Box->new(
      foo => 'bar',
  );

The C<new> constructor lets you create a new B<Rex::Box> object.

So no big surprises there...

Returns a new B<Rex::Box> or dies on error.

=cut

sub new {
	my $class = shift;
	my $self  = bless { @_ }, $class;
	return $self;
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


before 'Box:exists' => sub {
	print "### A:exists ###\n";
};
#before 'exists' => sub {
#	print "### exists ###\n";
#};

=pod

=head2 Box:create

lists the virtual machines in the RexConfig hoster group

=cut

desc "create";
task "create", group => "hoster", sub {
    my ($params) = @_;

    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    die "--name=$params->{name} ambiguous, please use another name" if ($params->{name} eq '1');
    
    my $server = Rex::get_current_connection()->{server};
    my $base_box = $cfg->{Base}->{TemplateImages}->{$cfg->{Base}->{DefaultBox}};
    
    
    #TODO: refuse to name a vm with chars you can't use in a hostname
    #refuse to create if the host already exists - test not only libvirsh, but dns etc too (add a --force..)
#    my $host = do_task("Box:status");  #BUG? this do_task returns nothing :() - should work as we're on the same host, so could use the same forked process... else  IPC
    my $host = _status($params->{name});
    #print 'info'.Dumper $host;
    if (!defined($host)) {
        print "Creating vm named: $params->{name} on $server\n";
        vm create => $params->{name},
		network => [
         {  type    => "bridge",
            bridge  => "br100",
         },],
         storage     => [
             {
                file   => $cfg->{hosts}->{$server}->{ImageDir}.$params->{name}.".img",
                template   => $cfg->{hosts}->{$server}->{TemplateImageDir}.$base_box->{ImageFile},
             },
          ],
          graphics => { type=>'vnc',
                        port=>'-1',
                        autoport=>'yes',
                        listen=>'*'
          };
        print "Starting vm named: $params->{name} \n";
          
        vm start => $params->{name};
    } else {
    	#TODO: can't do this - without IPC, the initial task doesn't know about the die, so continues on
    	#die "$params->{name} already exists - you can --force it if you need\n" unless ($params->{force});
    	print "using exiting host: $params->{name}\n";
    	vm start => $params->{name} unless ($host->{status} eq 'running');
    }      

	#I'd like to move this into an 'after Box:exists but something goes wrong.
	#TODO: and now test for name->ip->mac address..
	#TODO: and test that the ping succeeds - it might need starting!
	my $ping = run "ping -c1 $params->{name}";
	$ping =~ /\((.*?)\)/;
	my $ping_ip = $1;
	
    my $ips;
    my $count = 0;
    while (!defined($ips) || !defined($$ips[0])) {
		__use_vnc($params->{name}, $base_box->{user}, $base_box->{password}) if ($count > 0); #kick the server with vnc if we don't get instant success'
        print "   try\n";
        $ips = __vm_getip($params->{name});
        sleep(1);
	    $count++;
    }
    
    #TODO: terrible assumption - how to deal with more than one network interface per host?
    print "IP: --$$ips[0]--\n";
    if ($$ips[0] eq $ping_ip) {
    	print "hostname already mapped to IP, and mac - flying by the seat of our pants\n";
    }

	VMTASK: {
		print "Setting user to ".$base_box->{user}."\n";
		
		#TODO: I wish this was not in the Rexfile, as imo its part of the VM only creation..
		#but, to run it, we need the vm's user details..
		#OH. those are also vm details..
        my $vmtask = Rex::TaskList->get_task("Box:set_hostname");
        $vmtask->set_user($base_box->{user});
        $vmtask->set_password($base_box->{password});
        pass_auth(); #TODO: it bothers me that pass_auth works different from user() and password()
		# if ($base_box->{auth} eq 'pass_auth');
		
		$vmtask->run($$ips[0], params => $params);
	}
};

around create => sub {
    my ($server, $server_ref, $params) = @_;
	##TODO: this bothers me, I think the commandline param should be available here too
	print "### test on $server $params->{name}###\n";
};


=pod

=head2 Box:list

lists the virtual machines in the RexConfig hoster group

=cut

desc "lists the virtual machines in the RexConfig hoster group";
task "list", group => "hoster", sub {    
	print Dumper vm list => "all";
};


desc "start --name=";
task "start", group => "hoster", "name", sub {    
    my ($params) = @_;
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    
    print "Starting vm named: $params->{name} \n";
	print Dumper vm start => $params->{name};
};
desc "stop --name=";
task "stop", group => "hoster", "name", sub {    
    my ($params) = @_;
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    
    print "Stoping vm named: $params->{name} \n";
	print Dumper vm shutdown => $params->{name};
};

desc "status --name=";
task "status", group => "hoster", sub {  
    my ($params) = @_;  
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    return _status($params->{name});
};
#extracted because using $host = needs('Box:status', $params) does not work
sub _status {
	my $hostname = shift;

    my $list = vm list => "all";
    foreach my $test (@$list) {
    	if ($test->{name} eq $hostname) {
    		Rex::Logger::info(Dumper $test);

    		return $test;
    	}
    }
    return;
}

desc "info --name=";
task "info", group => "hoster", sub {  
    my ($params) = @_;  
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    print Dumper vm dumpxml => $params->{name};
};


desc "delete --name=";
task "delete", group => "hoster", "name", sub {    
    my ($params) = @_;
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    
    my $host = _status($params->{name});
    unless ($host) {
    	print "vm '$params->{name}' not found\n";
    	return -1;
    }
	if ($params->{stop} && !($host->{status} eq 'shut off')) {
		vm shutdown => $params->{name};
		print "stopping $params->{name} ";
		until ($host->{status} eq 'shut off') {
			print '.';
			sleep(1);
			$host = _status($params->{name});
		}
		print "\n";
	}
    unless ($host->{status} eq 'shut off') {
    	print "vm '$params->{name}' not stopped (add --stop to force)\n";
    	return -1;
    }

    my $server = Rex::get_current_connection()->{server};
    
    print "Deleting vm named: $params->{name}from $server \n";
	vm delete => $params->{name};
    print "Deleting image named: vm_imagesdir.$params->{name}.img \n";
    rm $cfg->{hosts}->{$server}->{ImageDir}.$params->{name}.".img";
	
};



desc "vnc port";
task "vnc", group => "hoster", "name", sub {
    my ($params) = @_;
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    
    
    print "getting vnc server:port for vm named: $params->{name} \n";
#TODO: replace * with server name - how do we get the name of the server?
    my $vnc = vm vncdisplay => $params->{name};
    print "VNC: $vnc\n";
};

desc "ip";
task "ip", group => "hoster", "name", sub {
    my ($params) = @_;
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};
    
    print "getting ip for vm named: $params->{name} ... ".hostname()." \n";

    my $ips = __vm_getip($params->{name});
    print "IP: ".join(',', @$ips)."\n";
};


sub __use_vnc {
    my $vmname = shift;
    my $username = shift;
    my $password = shift;
    
    my $server = Rex::get_current_connection()->{server};
    my $vncport = vm vncdisplay => $vmname;
    $vncport =~ s/.*:(.*)/$1/;
    $vncport = 5900+$1;
    print "---- vnc to $vmname on $username @ $server:$vncport\n";
   
    #TODO: use the vnc console to trigger traffic between the vmserver (where arp is running) and the vm
	my $vnc = Net::VNC->new({hostname => $server, port=>$vncport});
	#$vnc->depth(8); - don't do this.
	$vnc->login;
	#in case we need to log in?
    $vnc->send_key_event_string($username);
    $vnc->send_key_event(0xff0d);
	sleep(1);
    $vnc->send_key_event_string($password);
    $vnc->send_key_event(0xff0d);
	sleep(1);
    $vnc->send_key_event_string('ping -c 2 '.$server);
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
            $addrs{lc($2)} = $1;
        }
    }
  
	my $opt = vm dumpxml => $vmname;
	my $interfaces = $opt->{devices}->{interface};
	#i presume that if there are 2 network if's that this is a list..
	$interfaces = [$interfaces] unless (ref($interfaces) eq 'ARRAY');
	
	my @ips;
	foreach my $if (@{$interfaces}) {
	    my $mac = lc($if->{mac}->{address});
	    print "\t$mac => $addrs{$mac}\n" if $addrs{$mac};
	    push(@ips, $addrs{$mac});
	}
	return \@ips;
};


#This call should probably go into a Box::Host cfg module or something
use Rex::Commands::Sysctl;
use Rex::Commands::Upload;

#While I can dynamically change the definition of the group, or set the hostname, I can't set how to auth to it.
#tbh, auth shouldn't really be a global, its host dependent
user('root');
password('rex');
desc "set_hostname --name=";
task "set_hostname", group=> 'vm', sub {    
    my ($params) = @_;
    
    my $server = Rex::get_current_connection()->{server};
    Rex::Logger::info("running set_hostname on $server, setting name to $params->{name}");
    
    #given that the list of params is built by rex, can it error out?
    die 'need to define a --name= param' unless $params->{name};

    run "echo $params->{name} > /etc/hostname ; /etc/init.d/hostname.sh";
    #CAREFUL: don't call run sysctl '' - as sysctl already has a run in it.
    my $newhost = sysctl "kernel.hostname='$params->{name}'";
    #die "failed to set hostname (should be $params->{name}) is $newhost;\n" unless ($params->{name} eq $newhost);

    #get dhclient to tell the dhcp server its name too
    run "echo send host-name \\\"$params->{name}\\\"\\\; >> /etc/dhcp/dhclient.conf ; dhclient";
    
    #throw the ssh key over.
    #shame that upload doesn't do dir's
    run 'mkdir .ssh ; chmod 700 .ssh';
    upload $ENV{HOME}.'/.ssh/id_rsa', '.ssh';
    upload $ENV{HOME}.'/.ssh/id_rsa.pub', '.ssh/authorized_keys';

};



1;

=pod

=head2 Box Module

quickly manage virtual machine configurations and deployments

=head2 USAGE

 rex -H $host Box:create --name=baz

Or, to use it from a project's Rexfile

 use Box;
    
 task "create", sub {
    Box::create({
       name => "baz"
    });
 };

=head1 SUPPORT

email Sven Dowideit <SvenDowideit@fosiki.com>

=head1 AUTHOR

Copyright 2012 Sven Dowideit <SvenDowideit@fosiki.com>
