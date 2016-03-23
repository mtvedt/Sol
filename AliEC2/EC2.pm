package AliEC2::EC2;

use VM::EC2;
use strict;
use warnings;
use utf8;
use Encode qw(decode);
use Dancer;
use Log::Log4perl qw< :easy >;
use Config::Simple;
use MIME::Base64;

setting log4perl => {
   tiny => 0,
   config => '
      log4perl.logger                      = DEBUG, OnFile, OnScreen
      log4perl.appender.OnFile             = Log::Log4perl::Appender::File
      log4perl.appender.OnFile.filename    = sample-debug.log
      log4perl.appender.OnFile.mode        = append
      log4perl.appender.OnFile.layout      = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.OnFile.layout.ConversionPattern = [%d] [%5p] %m%n
      log4perl.appender.OnScreen           = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.OnScreen.color.ERROR = bold red
      log4perl.appender.OnScreen.color.FATAL = bold red
      log4perl.appender.OnScreen.color.OFF   = bold green
      log4perl.appender.OnScreen.Threshold = ERROR
      log4perl.appender.OnScreen.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.OnScreen.layout.ConversionPattern = [%d] >>> %m%n
   ',
};
setting logger => 'log4perl';

use Exporter qw(import);
our @EXPORT_OK = qw(new spawnVirtualMachine);

my $ec2config;

sub new {
	my ($class, $conf, %args) = @_;
	$ec2config = $conf;
	return bless { %args }, $class;
};

sub spawnVirtualMachine {
	my $self = shift;
	my $jobID = shift;
	my $script = shift;

	#error $ec2config->param('ec2_access_key');
	#error $ec2config->param('ec2_secret_key');
	#error $ec2config->param('ec2_url');
    
    my $id = "error";
    
    error "reading config file ".$ENV{ALIEC2_HOME}."/ec2.conf";
	my $ec2config = new Config::Simple($ENV{ALIEC2_HOME} . "/ec2.conf");
	
	error "Connecting to OpenStack";
	my $ec2 = VM::EC2->new(
		-access_key => $ec2config->param('ec2_access_key'), 
		-secret_key => $ec2config->param('ec2_secret_key'),
		-endpoint   => $ec2config->param('ec2_url'));

	if(!$ec2) {
		error "Can't connect to OS";
		return $id;
	}
	
	my $confImgType = $ec2config->param('image_type');

	my @images = $ec2->describe_images($confImgType);
	unless(@images) {
		error "EC2: " . $ec2->error;
		return $id;
	}

        if($ec2config->param('enable_auto_snapshots') eq 'true'){

         my @snapshot_images = $ec2->describe_images('auto-snapshot');
         if(@snapshot_images){
         @images = @snapshot_images;
         }


        } 

        
	my @runningInstances = $ec2->describe_instances({'instance_type'=>$ec2config->param('instance_type')});
	my $numRunningInstances = @runningInstances;


        print "The running instances are: @runningInstances \n";

        my $maxNumInstances = $ec2config->param('max_num_vms');

        error "||||||||||||||||||||||||||||||||||||||||||||||| There are $numRunningInstances instances running ||||||||||||||||||||||||||||||||||||||||||| \n";
        error "11111111111111111111111111111111111111111111111 The current limit is $maxNumInstances 11111111111111111111111111111111111111111111111111111 \n";

	if($numRunningInstances >= $ec2config->param('max_num_vms')) {
		# cleanup stopped instances?
		error "We're at max running instances";
		return $id;
	}
	
	my $userdata = decode('UTF-8', $script);
	
	error "USERDATA $userdata";
	
	# create and start a new instance
	# with the user data provided above.
	error "Starting instance of type: $confImgType";
	my @instances = $images[0]->run_instances(
			-instance_type => $ec2config->param('instance_type'),
			-min_count => 1,
			-max_count => 1,
			-security_group => $ec2config->param('security_group'),
			-key_name => $ec2config->param('key_name'),
			-user_data => $userdata);

    
    
	foreach(@instances) {
#		$_->add_tags(Role => 'worker_node');
		$id = $_->privateDnsName;
		error "Instance with id: $id started";
	}
	
	
	if(!@instances) {
		error "EC2 error $ec2->error_str";
		return $id;
	}


#        die("Planned termination");

	
	return $id;
};

sub deleteVirtualMachine {
	my $self = shift;
	my $machineID = shift;
    
    error "reading config file ".$ENV{ALIEC2_HOME}."/ec2.conf";
	my $ec2config = new Config::Simple($ENV{ALIEC2_HOME} . "/ec2.conf");
	
	error "Connecting to OpenStack";
	my $ec2 = VM::EC2->new(
		-access_key => $ec2config->param('ec2_access_key'), 
		-secret_key => $ec2config->param('ec2_secret_key'),
		-endpoint   => $ec2config->param('ec2_url'));

	if(!$ec2) {
		error "Can't connect to OS";
		return 2;
	}

	my @runningInstances = $ec2->describe_instances({
	    'privateDnsName' => $machineID
	});
	
	my $num = @runningInstances;
	
	foreach(@runningInstances) {
	    if($_->privateDnsName eq $machineID) {
	        error "Found Instance ". $_->privateDnsName .". Deleting it.";
	        $ec2->terminate_instances($_);
	        return 0;
	    }
	}
	
	if( $num == 0 ) {
	    error "No such instance $machineID";
	    return 3;
	}
	
	error "An error occured while deleting $machineID";
	 
	return 1;
};

sub getVirtualMachines {
        

    error "reading config file ".$ENV{ALIEC2_HOME}."/ec2.conf";
        my $ec2config = new Config::Simple($ENV{ALIEC2_HOME} . "/ec2.conf");

        error "Connecting to OpenStack";
        my $ec2 = VM::EC2->new(
                -access_key => $ec2config->param('ec2_access_key'),
                -secret_key => $ec2config->param('ec2_secret_key'),
                -endpoint   => $ec2config->param('ec2_url'));

        if(!$ec2) {
                error "Can't connect to OS";
                return "error";
        }

        my @runningInstances = $ec2->describe_instances({'instance_type'	=> 'cernvm-machine'});

        return @runningInstances;
};

sub createInstanceSnapshot {

        my $self = shift;
        my $machineID = shift;

    error "reading config file ".$ENV{ALIEC2_HOME}."/ec2.conf";
        my $ec2config = new Config::Simple($ENV{ALIEC2_HOME} . "/ec2.conf");

        error "Connecting to OpenStack";
        my $ec2 = VM::EC2->new(
                -access_key => $ec2config->param('ec2_access_key'),
                -secret_key => $ec2config->param('ec2_secret_key'),
                -endpoint   => $ec2config->param('ec2_url'));

        if(!$ec2) {
                error "Can't connect to OS";
                return 2;
        }

        my @runningInstances = $ec2->describe_instances({
            'privateDnsName' => $machineID
        });

        my $num = @runningInstances;

        foreach(@runningInstances) {

            if($_->privateDnsName eq $machineID) {
                error "Found Instance ". $_->privateDnsName .". Creating snapshot...";
               $ec2->create_image(-instance_id=>$_,-name=>'auto-snapshot');
               $ec2->register_image(-name=>'auto-snapshot');
                return 0;
            }
        }

        if( $num == 0 ) {
            error "No such instance $machineID";
            return 3;
        }

        error "An error occurred while creating the EC2 snapshot. A snapshot is possibly already present.";

#my @snapshots = $ec2->describe_snapshots();

#print "The current snapshots are: @snapshots \n";

#my @volumes = $ec2->describe_volumes();

#  foreach(@volumes) {

#  print "The current VolumeID is $_->volume_id , or $_->id , or perhaps just $_";

#  $ec2->create_snapshot($_);

#}

#  print "The current volumes are: @volumes \n";

#  my @snapshots2 = $ec2->describe_snapshots();

#print "The snapshots are now: @snapshots2 \n";



        return 1;



}

1;



