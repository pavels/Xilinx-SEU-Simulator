#!/usr/bin/perl
use strict;
use warnings;
use Expect;
use threads;
use IO::Socket::INET;
use Getopt::Long;
use Pod::Usage;


my $fpgaed_comm = "fpga_edline";
my $bitgen = "bitgen";
my $xc3sprog = "./xc3sprog";

my $PORTNO = "12345";

# ============== END OF CONFIG ==============
my $Hfpgaed;
my $UDPSocket;

sub bitgen
{
    my $bitsrc;
    my $ncdsrc;
    my $bitdest;
    {
	no warnings;
	$bitsrc = @_[0];
	$ncdsrc = @_[1];
	$bitdest = @_[2];
    }
    #print "Generating bitstream ...";
    system ($bitgen." -d -w -g ActiveReconfig:Yes -g Persist:Yes -r " . $bitsrc . " " . $ncdsrc . " " . $bitdest . " 1>/dev/null");
    #print "Done\n";
}

sub xprog
{
    my $bitstream;
    {
	no warnings;	
	$bitstream = @_[0];
    }
    print "Programing bitstream ...";
    system($xc3sprog. " -p 0 " . $bitstream . " 1>/dev/null 2>/dev/null");
    print "Programming done\n";
}

sub getLUTSize
{
    my ($var) = @_;

    $var =~ s/([a-z]+)/\$$1/ig;
    my %a;
    @a{$var =~ /(\$\w+)/g} = 1;
    my @v = sort keys %a;
    $var =~ s/~/!/g;
    $var =~ s/\*/\&\&/g;
    $var =~ s/\+/\|\|/g;
    $var =~ s/@/ xor /g;
    my @LUT;
    eval join "",(map{"my $_; for $_ (0,1){"}@v),"push(\@LUT,($var)?1:0)","}"x@v;
    return  scalar(@v);
}

sub changeLUT
{
    my $var;
    my $pos;
    {
	no warnings;	
	($var) = @_[0];
	$pos = @_[1];
    }

    $var =~ s/([a-z]+)/\$$1/ig;
    my %a;
    @a{$var =~ /(\$\w+)/g} = 1;
    my @v = sort keys %a;
    $var =~ s/~/!/g;
    $var =~ s/\*/\&\&/g;
    $var =~ s/\+/\|\|/g;
    $var =~ s/@/ xor /g;
    my @LUT;
    eval join "",(map{"my $_; for $_ (0,1){"}@v),"push(\@LUT,($var)?1:0)","}"x@v;
    $LUT[$pos] = $LUT[$pos]?0:1;
    my $new_eq = "";
    my $eq_proc = join "",(map{"if($_ == 0){\$new_eq .= \"~\"}; \$new_eq.=substr(\'$_\',1).\"*\";"}@v),"\$new_eq=substr(\$new_eq,0,-1);";
    eval join "","my \$cnt=0;",(map{"my $_; for $_ (0,1){"}@v),"if(\$LUT[\$cnt]==1){\$new_eq.=\"(\";",$eq_proc,"\$new_eq.=\")+\";};\$cnt++;","}"x@v;
    $new_eq = "(" . substr($new_eq,0,-1) . ")";
    return $new_eq;
}

sub term_clean
{
    print "\nTERMINATING...\n";
    $Hfpgaed->send("\n");
    $Hfpgaed->expect(15,"Command:");

    $Hfpgaed->send("save design mod_design\n");
    $Hfpgaed->expect(15,"Command:");

    $Hfpgaed->send("exit\n");
    $Hfpgaed->expect(undef);

    exit 0;
}

sub bitgen_async
{

    my $confid = shift;
    my $bitfile = shift;

    bitgen($bitfile,"mod_design" . $confid . ".ncd","mod_design" . $confid . ".bit");
    bitgen("mod_design" . $confid . ".bit","rec_design" . $confid . ".ncd","rec_design". $confid  .".bit");

    return 1;
}

sub wait_for_ctl
{
    $UDPSocket->send("FGEN");
    my $msg = "";
    while($msg ne "CONTINUE")
    {
	$UDPSocket->recv($msg,128);
    }
}


# ================== MAIN ===================
my $ncdfile = "";
my $bitfile = "";
my $module = "";
my $faultcount = 1;
my $help;

GetOptions( "ncd=s" => \$ncdfile,
            "bit=s"  => \$bitfile ,
	    "module=s" => \$module,
	    "help|?" => \$help,
	    "faultcount=i" => \$ncdfile
);

if(length($ncdfile) < 1 or length($bitfile) < 1 or length($module) < 1 or $help)
{
    pod2usage( -verbose => 2, -noperldoc => 1 );
    exit;
}

$Hfpgaed = new Expect;
$Hfpgaed->raw_pty(1);
$Hfpgaed->log_stdout(0);

$Hfpgaed->spawn($fpgaed_comm)
    or die "ERROR: Failed to load fpga_edline";

$SIG{INT} = \&term_clean;

$Hfpgaed->expect(15,"Command:");

print "fpga_edline started. Loading design.\n";

$Hfpgaed->send("open design " . $ncdfile . "\n");
$Hfpgaed->expect(15,"is an NCD");

$Hfpgaed->expect(15,
               [ "Enter Y or N:" => sub {$Hfpgaed->send("n\n");
					 $Hfpgaed->expect(15,"Command:");}],
               [ "Command:" ]
              );

$Hfpgaed->send("\n");
$Hfpgaed->expect(15,"Command:");

$Hfpgaed->send("setattr main edit_mode read-write\n");
$Hfpgaed->expect(15,"Command:");

print "Parsing design.\n";

$Hfpgaed->send("select bel " . $module . "* \n");
$Hfpgaed->expect(15,"Command:");

$Hfpgaed->send("getattr \n");
$Hfpgaed->expect(15,"Command:");

my %used_components_tmp;
@used_components_tmp{$Hfpgaed->before =~ /^Comp = (.+)/gm}=1;
my @used_components = keys %used_components_tmp;

my %LUTs;

foreach my $component (@used_components){
    $Hfpgaed->send("getattr comp " . $component . "\n");
    $Hfpgaed->expect(15,"Command:");
    $Hfpgaed->before =~ /^F = (.+)/gm;
    $LUTs{($component . " F")} = $1;
    $Hfpgaed->before =~ /^G = (.+)/gm;
    $LUTs{($component . " G")} = $1;
}


my @LUTkeys = keys %LUTs;

print "Found ",scalar(keys %LUTs)," LUTs\n";

print "Initialize device.\n";
&xprog($bitfile);

my $oldconf = "1";
my $newconf = "0";
my @oldgeneratedfaults = ();
my @newgeneratedfaults = ();
my $thr = undef;

$UDPSocket=new IO::Socket::INET->new(LocalPort=>$PORTNO, Proto=>'udp');
print "Waiting for controller to connect\n";

my $msg = "";

while($msg ne "CONNECT")
{
    $UDPSocket->recv($msg,128);
}
$UDPSocket->send("OK");

while(1)
{
    if(defined $thr)
    {
	while($thr->is_running()){select(undef, undef, undef, 0.1);}
    }

    $oldconf = $newconf;
    $newconf = $oldconf eq "1" ? "2" : "1";


    #======== FAULT GENERATION ============
    my $fgencount = 0;
    @oldgeneratedfaults = @newgeneratedfaults;
    @newgeneratedfaults = ();
    my %newLUTS = ();
    while($fgencount < $faultcount)
    {	
	my $lutid = int(rand(scalar(keys %LUTs)));
	my $random_position = int(rand(2 ** getLUTSize($LUTs{$LUTkeys[$lutid]}) - 1));
	my $count = grep {$_ eq $LUTkeys[$lutid] . " " . $random_position} @newgeneratedfaults;
	if($count > 0){next;}

	print "Generating fault LUT: " . $LUTkeys[$lutid] . " " . $random_position. "\n";
	if (exists $newLUTS{$LUTkeys[$lutid]})
	{
	    my $newlut = changeLUT($newLUTS{$LUTkeys[$lutid]},$random_position);
	    if (length($newlut) == 2){ next; }
	    $newLUTS{$LUTkeys[$lutid]} = $newlut;
	}
	else
	{
	    my $newlut = changeLUT($LUTs{$LUTkeys[$lutid]},$random_position);
	    if (length($newlut) == 2){ next; }
	    $newLUTS{$LUTkeys[$lutid]} = changeLUT($LUTs{$LUTkeys[$lutid]},$random_position);
	}
	push(@newgeneratedfaults,$LUTkeys[$lutid] . " " . $random_position);
	$fgencount++;
    }

    #======== FAULT GENERATION ============

    #======== FAULT SETTING ===============
    foreach my $key (keys %newLUTS) {
	$Hfpgaed->send("setattr comp " . $key ." " .$newLUTS{$key} . "\n");
	$Hfpgaed->expect(15,"Command:");
    }


    $Hfpgaed->send("save design mod_design" . $newconf  . "\n");
    $Hfpgaed->expect(15,"Command:");
    #======== FAULT SETTING ===============


    #======== FAULT FIX ============
    foreach my $key (keys %newLUTS) {
	$Hfpgaed->send("setattr comp " . $key ." " . $LUTs{$key} . "\n");
	$Hfpgaed->expect(15,"Command:");
    }

    $Hfpgaed->send("save design rec_design" . $newconf  . "\n");
    $Hfpgaed->expect(15,"Command:");
    #======== FAULT FIX ============

    $thr = threads->create(\&bitgen_async, $newconf, $bitfile);
    $thr->detach();

    if($oldconf ne "0")
    {
	&xprog("mod_design" . $oldconf . ".bit");
	
	$UDPSocket->send("FSET");
	foreach my $key (@oldgeneratedfaults) {
	    $UDPSocket->send($key);
	}
	$UDPSocket->send("###");
	&wait_for_ctl();
	&xprog("rec_design" . $oldconf . ".bit");
    }

}

=head1 fault-generator - Program for injecting faults into Xilinx FPAG Bitstream


This program generates partial bitstream with injected faults and programs it into FPGA
It is testbench driven. After initialization, it will wait for testbench driver to connect.
Connection is made through UDP.

=head2 PARAMETERS

    --ncd <file.ncd>       = NCD file from Xilinx tools
    --bit <file.bit>       = Initial bitstream
    --module <module_name> = Name of module (instance) into which inject faults
    [--faultcount <num>]   = How many faults to inject simultaneously
    --help                 = This help

=head2 COMMUNICATION

Communication is made using UDP packets
fault-generator is server for this purpose.
fault-generator will emit following commands (ASCII):
    
    OK   - after successfully connecting of testbench driver 
    FSET - after this command, list of generated fault will follow
           each fault is separate packet
           list is terminated with “###” escape sequence
    FGEN - means, that target device is programmed and ready for test

testbench should reply with following:
    
    CONNECT  - is sent immediately after connecting to fault-generator
    CONTINUE - as reply to FGEN after all test are finished

=head2 CONFIGURATION

At the beginning of this script, there is couple of configuration variables like  paths to Xilinx tools and port for communication. Set these prior to usage accordingly.

 
=head1 AUTHOR Pavel Sorejs



=cut
