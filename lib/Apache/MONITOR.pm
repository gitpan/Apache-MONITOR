package Apache::MONITOR;

require 5.005_62;
use strict;
use vars qw($VERSION @EXPORTER @ISA);
use warnings;

use DB_File;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our @EXPORT = qw(SUBSCRIBE UNSUBSCRIBE NOTIFY SHOW);
our $VERSION = '0.01';

use URI::Escape;
use Apache::Constants qw(:common :http :response :methods);




sub handler {
        my $r = shift;
        #$is_monitor = 0;
        $r->warn( "prr_handler 1");
        return DECLINED unless $r->method() eq 'MONITOR' ;
        $r->warn( "prr_handler 2");
 
        #$is_monitor = 1;
        #$r->method('GET');
        $r->method_number(M_GET);
 
        return OK;
}

sub hp_handler {
        my $r = shift;
	$r->warn( "handler 1");
        return DECLINED unless $r->method() eq 'MONITOR' ;
        #return DECLINED unless $is_monitor;
	$r->warn( "hp handler 2");
 
	#$r->method('MONITOR');
	#$r->method_number(M_INVALID);
 
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&monitor_handler);
	$r->warn( "hp handler 3");
 
        return OK;
}

 
sub add_subscription
{
        my ($r,$uri,$filename,$reply_to) = @_;

        my $dir = $r->dir_config('MonitorDataDir');
        my $mon_prefix = $r->dir_config('MonitorUrlPrefix');

	my $monitor_url = $mon_prefix; 
	my %uris;
	my %monitors;


	open(LOCK,">$dir/lock") || die("unable to open $dir/lock, $!");
	flock(LOCK,2);	

	dbmopen( %uris , "$dir/uris", 0666) || die("unable to open $dir/uris, $!");	
	if(! exists $uris{$uri})
	{
		my $now = time();
		my $value = join(' ', ($uri,$filename,$now) );
		$uris{$uri} = $value;
	}
	dbmclose(%uris);

	dbmopen( %monitors , "$dir/monitors", 0666) || die("unable to open $dir/monitors, $!");	
	foreach my $muri (keys %monitors)
	{
		my $value = $monitors{$muri};
		my ($u,$re) = split (/ /,$value);
		if( ($u eq $uri) && ($re eq $reply_to) )
		{
			
			dbmclose(%monitors);
			close(LOCK);
			$r->warn("$u already monitored to ($re)");
			die("$u already monitored to ($re)");
			return $muri;
		}
	}
	my $id = time() . $$;	
	$monitor_url .= $id;
	$monitors{$monitor_url} = "$uri $reply_to";
	dbmclose(%monitors);
	close(LOCK);


	return $monitor_url;
}
 
 
 
sub monitor_handler
{
        my $r = shift;

	if( ! is_monitorable($r,$r->filename) )
	{
		return HTTP_METHOD_NOT_ALLOWED;
	}

 
        my $reply_uri = $r->header_in( 'Reply-To' );
	$r->warn( "monitor_handler 3");
 
        if( !defined $reply_uri || !$reply_uri)
        {
                return BAD_REQUEST;
        }

	my $host = $r->header_in( 'Host' );
        if( !defined $host || !$host)
        {
                return BAD_REQUEST;
        }

 
        my $mon_url = add_subscription($r,"http://$host" . $r->uri,$r->filename,$reply_uri);
 
        $r->header_out("Location" => $mon_url );
	$r->status(201);

        #$r->header_out("Content-Length" => 0);
 
        $r->send_http_header();
 
        $r->warn( "Filename " , $r->filename, "\n" );
        $r->warn( "Uri " , $r->uri, "\n" );
        $r->warn( "pathinfop " , $r->path_info, "\n" );
 
        return OK;
}

sub moo
{
        my $r = shift;

	

        my $dir = $r->dir_config('MonitorDataDir');
	my $host = $r->header_in( 'Host' );
	my $mon_uri = 'http://' . $host . $r->uri();

	if($r->method eq "GET")
	{
	my %uris;
	my %monitors;

	open(LOCK,">$dir/lock") || die("unable to open $dir/lock, $!");
	flock(LOCK,1);	

	dbmopen(%monitors , "$dir/monitors", 0666) || die("unable to open $dir/monitors, $!");
	my $value = $monitors{$mon_uri};
	dbmclose(%monitors);
	close(LOCK);

	if(!defined $value)
	{
		return NOT_FOUND;
	}	


	my ($u,$re) = split( / / , $value);

        $r->send_http_header("text/html" );
	$r->print( qq{
	<html>
	<head>
	<title>Monitor $mon_uri</title>
	</head>
	<body>
	
	<h1>Monitor $mon_uri</h1>

	<p>Monitors: <a href="$u">$u</a><br />
	Reply-To: <a href="$re">$re</a>
	</p>
	<!--
	<p><b>Edit your daily notification period</b><br />
	<form method="POST">
	From <input type="text" size="2" /> o'clock until
	<input type="text" size="2" /> o'clock.
	<input value="Change" type="submit" />
	</form>
	</p>
	-->

	<form method="POST">
	<input type="hidden" name="method" value="DELETE" />
	<input value="Unsubscribe" type="submit" />
	</form>
	</body>
	</html>
	});
	return OK;

	}
	elsif($r->method eq "POST")
	{
	my %params = $r->content;
	if( exists($params{method}) && $params{method} eq "DELETE")
	{

	my %uris;
	my %monitors;
	my $uri_still_monitored = 0;

	open(LOCK,">$dir/lock") || die("unable to open $dir/lock, $!");
	flock(LOCK,2);	

	dbmopen(%monitors , "$dir/monitors", 0666) || die("unable to open $dir/monitors, $!");
	if(!exists($monitors{$mon_uri}))
	{
		dbmclose(%monitors);
		close(LOCK);
		return NOT_FOUND;
	}	
	my ($monitored_uri,$re) = split(/ / , $monitors{$mon_uri});
	delete $monitors{$mon_uri};
	foreach my $muri (keys %monitors)
	{
		die("XXXXX") if($mon_uri eq $muri);
		my $value = $monitors{$muri};
		my ($u,$re) = split(/ / , $value);
		if($u eq $monitored_uri)
		{
			$uri_still_monitored = 1;
			last;
		}
	}
	dbmclose(%monitors);
	if(!$uri_still_monitored)
	{
		dbmopen(%uris , "$dir/uris", 0666) || die("unable to open $dir/uris, $!");
		delete $uris{$monitored_uri};
		dbmclose(%uris);
	}
	close(LOCK);
	
        $r->send_http_header("text/html" );
	$r->print( qq{
	<html>
	<head>
	<title>Deleted Monitor $mon_uri</title>
	</head>
	<body>
	
	Monitor $mon_uri has been deleted. 
	</body>
	</html>
	});

        return OK;
	}
	}
        return OK;
}
 

sub is_monitorable
{
	my ($r,$filename) = @_;
	if(-f $filename)
	{
		return 1;
	}

	return 0;
	
}







sub SUBSCRIBE
{
	require LWP::UserAgent;
	@Apache::MONITOR::ISA = qw(LWP::UserAgent);

	my $ua = __PACKAGE__->new;
	
	my $args = @_ ? \@_ : \@ARGV;

	my ($url,$reply_to) = @$args;
	my $req = HTTP::Request->new('MONITOR' => $url );

	$req->header('Reply_To' => $reply_to );
	my $res = $ua->request($req);

	if($res->is_success)
	{
		#print $res->as_string();
		#print $res->content;
		print "Monitor created at: ",$res->header('Location') , "\n";
	}
	else
	{
		print $res->as_string();
	}

}
sub UNSUBSCRIBE
{
	require LWP::UserAgent;
	@Apache::MONITOR::ISA = qw(LWP::UserAgent);

	my $ua = __PACKAGE__->new;
	
	my $args = @_ ? \@_ : \@ARGV;

	my ($mon_url) = @$args;
	my $req = HTTP::Request->new('DELETE' => $mon_url );

	my $res = $ua->request($req);

	if($res->is_success)
	{
		print $res->as_string();
		#print $res->content;
		print "Monitor deleted\n";
	}
	else
	{
		print $res->as_string();
	}

}

sub NOTIFY
{
	require LWP::UserAgent;
	@Apache::MONITOR::ISA = qw(LWP::UserAgent);
	my $ua = __PACKAGE__->new;
	my $args = @_ ? \@_ : \@ARGV;

	my ($dir) = @$args;

	my %uris;
	my %monitors;

	open(LOCK,">$dir/lock") || die("unable to open $dir/lock, $!");
	flock(LOCK,2);	

	dbmopen( %uris , "$dir/uris" , 0040) || die("unable to open $dir/uris, $!");	
	dbmopen( %monitors , "$dir/monitors" , 0040) || die("unable to open $dir/monitors, $!");	
	foreach my $monitored_uri ( keys %uris)
	{
		my $value = $uris{$monitored_uri};
		my ($u,$filename,$lastmod) = split(/ /,$value);
		#print "--$u $filename $lastmod\n";

		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                      $atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);		
	
		print "checking mtime of $monitored_uri\n";	
		next unless ($mtime > $lastmod);	

		print "...$monitored_uri has changed, getting monitors\n";

		# updating record with new lastmod
		$uris{$monitored_uri} = "$u $filename $mtime";

		foreach my $muri (keys %monitors)
		{
			my $value = $monitors{$muri};
			my ($u,$re) = split(/ / , $value);
			next unless ($u eq $monitored_uri);

			#my $req = HTTP::Request->new('GET' => $monitored_uri);
			#my $res = $ua->request($req);
			#my $body;
			#if($res->is_success)
			#{
			#	$body = $res->content;
			#}
			#else
			#{
			#	$body = $res->as_string();
			#}
			#$req->header('Reply_To' => $reply_to );

			if( $re =~ /^mailto:(.*)$/ )
			{
				my $to = $1;
				open(MAIL,"|mail $to -s \"Resource $monitored_uri has changed\"");
				print MAIL "Resource state has changed at ". localtime($mtime) ."\n";
				print MAIL "View the monitored resource: $monitored_uri\n";
				print MAIL "Edit your monitor: $muri\n";
				close(MAIL);
				print "   notified $re\n";	
			}
		}
		
	}
	dbmclose(%uris);
	dbmclose(%monitors);

	close(LOCK);

}

sub SHOW
{
	my $args = @_ ? \@_ : \@ARGV;

	my ($dir) = @$args;
	my %uris;
	my %monitors;

	open(LOCK,">$dir/lock") || die("unable to open $dir/lock, $!");
	flock(LOCK,1);	

	dbmopen( %uris , "$dir/uris" , 0040) || die("unable to open $dir/uris, $!");	
	dbmopen( %monitors , "$dir/monitors" , 0040) || die("unable to open $dir/monitors, $!");	
	foreach my $uri ( keys %uris)
	{
		my $value = $uris{$uri};
		my ($u,$filename,$t) = split(/ /,$value);
		print "$u $filename $t\n";
		foreach my $muri (keys %monitors)
		{
			my $value = $monitors{$muri};
			#print "-- $value --\n";
			my ($u,$re) = split(/ / , $value);
			if($u eq $uri)
			{
				print "     $muri ($re)\n";	
			}
		}
		
	}
	dbmclose(%uris);
	dbmclose(%monitors);

	close(LOCK);
}

1;
__END__

=head1 NAME

Apache::MONITOR - Implementation of the HTTP MONITOR method

=head1 SYNOPSIS

=head1 DESCRIPTION

This module implements a MONITOR HTTP method, which adds notifications to the
World Wide Web.

=head1 CONFIGURATION

httpd.conf:

  PerlSetVar MonitorDataDir /home/httpd/monitors
  PerlSetVar MonitorUrlPrefix http://myserver/monitors/
 
  PerlPostReadRequestHandler Apache::MONITOR
  PerlHeaderParserHandler Apache::MONITOR::hp_handler
 
  <Location /monitors/>
    SetHandler perl-script
    PerlHandler Apache::MONITOR::moo
  </Location>


crontab:

  # check for changes every 30 minutes
  0,30 * * * * perl -MApache::MONITOR -e NOTIFY /home/httpd/monitors &>/dev/null


=head1 COMMANDLINE TOOLS

Subscribe:

  perl -MApache::MONITOR -e SUBSCRIBE http://www.mopo.de mailto:joe@the.org

Show all subscriptions:

  perl -MApache::MONITOR -e SHOW /path/to/monitors

Check for changes and notify:

  perl -MApache::MONITOR -e NOTIFY /path/to/monitors


=head2 EXPORT

=head1 AUTHOR

Jan Algermissen, algermissen@acm.org


=cut
