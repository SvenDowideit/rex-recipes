#!rex -wT

use strict;
use warnings;

use Carp qw( confess );
$SIG{__DIE__}  = \&confess;
$SIG{__WARN__} = \&confess;

use Rex::Box;
use Rex::Commands::SCM;
use Rex::Commands::Pkg;
use Rex::Commands::Cron;
use Rex::Commands::User;

desc "create or set up a box --name=";
task "create", sub {
    my ($params) = @_;

    Rex::Logger::info( 'running create on ' . run 'uname -a' );

    #install a few things that I find useful
    #TODO: move this into my local config..
    update_package_db;
    install package => [qw/vim git subversion curl ssmtp/];

    #ssmtp setup
    #force quad to be in ssh known_hosts so that rsync just works
    run
'rsync -avz -e "ssh -o StrictHostKeyChecking=no" sven@quad:/etc/ssmtp/* /etc/ssmtp/';

#perl libraries needed by foswiki:
install package => [qw(libapache-htpasswd-perl libcommon-sense-perl libcrypt-passwdmd5-perl libdevel-symdump-perl libdigest-sha1-perl liberror-perl libfile-remove-perl libhtml-parser-perl libhtml-tagset-perl libhtml-tidy-perl libhtml-tree-perl libjcode-pm-perl libjson-perl libjson-xs-perl liblocale-gettext-perl libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl libunicode-map-perl libunicode-map8-perl libunicode-maputf8-perl libunicode-string-perl liburi-perl libuuid-perl libdevel-monitor-perl libperl-critic-perl perltidy)];
#non perl deps:
install package => [qw(rcs apache2 dh-make-perl)];

    #if we were making a simple dev box :)
    #checkout foswiki
    #checkout 'foswiki_trunk', path=>'foswiki';

#create the user that will run the builds   
create_user "foswiki",
#root..       uid => 0,
       home => '/home/foswiki',
       comment => 'foswiki_nightly',
#       expire => '2011-05-30',
#       groups  => ['root', '...'],
       password => 'foswiki',
       system => 1,
#       ssh_key => "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQChUw..."
        ;
     
#cron job ot make it happen
 cron add => "foswiki", {
            minute => '5',
            hour   => '2',
            day_of_month    => '*',
            month => '*',
            day_of_week => '*',
            command => 'mkdir trunk ; cd trunk ; curl http://svn.foswiki.org/trunk/core/tools/autoBuildFoswiki.pl > autoBuildFoswiki.pl ; perl -w autoBuildFoswiki.pl > autoBuildFoswiki.log 2>&1',
         };    
};

Rex::Box->configurewith('create');

1;
__DATA__
need to set:
* domain
* tz
* adduser?
* apt-sources
its a basic debian setup with ssh and 'standard system utilities'

__REX__
need a vncdisplay so i can say 
rex create start connect --servername=newserver --box=debian
