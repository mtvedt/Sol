package AliEn::LQ::EC2;

use lib "/usr/local/share/perl5/";
use lib "/usr/local/lib64/perl5/";
use VM::EC2;
use MIME::Base64;
use AliEn::LQ;
use AliEn::Config;
use Config::Simple;

@ISA = qw( AliEn::LQ);
use strict;
use utf8;
use AliEn::Database::CE;
use Data::Dumper;
use Encode qw(encode);

use Net::Curl::Easy qw(:constants);
use Net::Curl::Form qw(:constants);

sub initialize {
    my $self = shift; 
    $self->{LOCALJOBDB}=new AliEn::Database::CE or return;
 return 1;
}

sub submit {

    my $self        = shift;
    my $classad     = shift;
   	#my $executable  = shift;
    my $command   = join " ", @_;

	$self->info("reading config file ".$ENV{ALIEC2_HOME}. "/settings.conf");
	my $ec2config = new Config::Simple($ENV{ALIEC2_HOME} . "/settings.conf");

	print "Command1: $command \n";
	
	my $error = 0;
	$command =~ s/"/\\"/gs;

	my $name=$ENV{ALIEN_LOG};
  	$name =~ s{\.JobAgent}{};
  	$name =~ s{^(.{14}).*$}{$1};

	$self->info("possible job agent ID: " . $1);
	my $execute=$command;
  	$execute =~ s{^.*/([^/]*)$}{$ENV{HOME}/$1}; #env HOME

  	system ("cp",$command, $execute);
    my $message.="$self->{SUBMIT_ARG}
    " . $self->excludeHosts() . " 
    $execute\n";

    $self->info("USING $self->{SUBMIT_CMD}\nWith  \n$message");

	
	# A context file is containing user data for a cern-vm instance,
	# contextualization data and a script which is executed at startup
	my $context_file = $ec2config->param('context_file');

        my $context;
            open(my $fh, '<', $context_file) or die "cannot open given VM context file  $context_file";
            {
                local $/;
                $context = <$fh>;
            }
            close($fh);

        my $encdata = encode('UTF-8', $context, Encode::LEAVE_SRC | Encode::FB_CROAK);


	my $data = $encdata;
	
	my $id = $$;
	my $host = $ec2config->param('host');
	my $url = "http://$host/spawn/$id";

	my $curl = new Net::Curl::Easy();

	$curl->setopt(CURLOPT_VERBOSE, 1);
	$curl->setopt(CURLOPT_NOSIGNAL, 1);
	$curl->setopt(CURLOPT_HEADER, 1);
	$curl->setopt(CURLOPT_TIMEOUT, 10);
	$curl->setopt(CURLOPT_URL, $url);

       

	my $curlf = new Net::Curl::Form();
	$curlf->add(CURLFORM_COPYNAME ,=> 'script', CURLFORM_COPYCONTENTS ,=> "$data");
	$curl->setopt(CURLOPT_HTTPPOST, $curlf);
		
	$curl->perform();
        
       



	
    return 0;
}

sub kill {

} 


sub getNumberRunning() {
   
}

sub getContactByQueueID {
    
}
