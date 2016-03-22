package test;

use strict;
use warnings;

our $VERSION = '0.1';

use Dancer2;
use Config::Simple;

use AliEC2::SQLite;
use AliEC2::EC2;
use MIME::Base64;

use threads;
use Log::Log4perl qw< :easy >;

use Encode qw(encode);




#set server => "10.0.0.215";
set port => 8080;


my $aliec2Home = $ENV{ALIEC2_HOME};

print "Using " . $aliec2Home . " as config directory\n";
my $ec2config = new Config::Simple($aliec2Home . '/settings.conf');
my $running = 1;

my $db = AliEC2::SQLite->new();
my $ec2 = AliEC2::EC2->new($ec2config);


get '/' => sub {
    template 'index';
};

sub setAlive {
    my $id = shift; 
    my $msg = $db->setStatus($id);
    error "$id is alive";
    return ("Setting " . $id . " as alive: " . $msg);
};

sub deleteVM {
    my $id = shift;
    my $msg = $db->delete($id);
    
    if($ec2->deleteVirtualMachine($id) == 0) {
        error "$id deleted";
    }
    else {
        error "couldn't delete $id";
    }
    
    return ("Deleting " . $id . ": " . $msg);
};

sub addVM {
    my $job = shift;
    my $script = shift;
    my $msg = "";
    
    error "Adding VM";

#    if($db->existJobID($job) == 1) {
        
#		error "Job id exist. ignoring";
#        return ("ERROR Job ID exist");
#    }
    
    my $id = $ec2->spawnVirtualMachine($job, $script);
    $msg = $db->add($id, $job);
    
    if($id eq "error") {
        $msg = "Error starting instance";
    }
   # return ("Adding " . $id . " with jobID " . $job . ": " . $msg);
    return $id;
};


get '/alive/:id' => sub {
no strict 'refs';
	my $id = param('id');
    setAlive($id);
};

get '/done/:id' => sub {
	my $id = param('id');
	error "$id is done";
   
        my $runningvms = $ec2->getVirtualMachines();

        my $minvms = $ec2config->param('min_num_vms');

	if($runningvms <= $minvms)
        {
         error "Need minimum $minvms VMs running.";
         error "There are currently $runningvms VMs running";
         error "VM $id will remain active.";
        }
        else
        {
        deleteVM($id);
        }
};

post '/spawn/:job' => sub {

        error "Spawn has been called";
	my $jid = param('job');
	
	my $script = param('script');
	
#	print $script;
	error "Script: $script";
    addVM($jid, $script);
};


#Thread for finding dead VMs
threads->create(sub {
	my $db = AliEC2::SQLite->new();
    while ( $running ) {
        sleep($ec2config->param('check_interval'));
        error "Looking for dead VMs";

        while((my $machine = $db->nextDeadMachine()) ne 0) {
        	error "$machine is dead. Killing it.";
        	deleteVM($machine);
        }
    }
});


print "Starting VMs (if needed)... \n";

my $context_file = $ec2config->param('context_file');

my $context;
    open(my $fh, '<', $context_file) or die "cannot open given VM context file  $context_file";
    {
        local $/;
        $context = <$fh>;
    }
    close($fh);

my $encdata = encode('UTF-8', $context, Encode::LEAVE_SRC | Encode::FB_CROAK);

#error "The context data for the VMs to start is: $encdata";

my $vmsrequired = $ec2config->param('min_num_vms');
my $vmsrunning = $ec2->getVirtualMachines();

print "Current number of VM(s) $vmsrunning \n";

foreach my $i ($vmsrunning+1..$vmsrequired) {
     print "Starting VM $i \n";
     addVM($i, $encdata);
}



print "Done! \n";



print "AliEC2 web service is ready \n";

dance;
$running = 0;
$db->end();
true;
to_app();
