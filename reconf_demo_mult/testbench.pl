#!/usr/bin/perl -w
use strict;
use warnings;
use Device::SerialPort;
use IO::Socket;

my $HOSTNAME = "localhost";
my $PORTNO = "12345";

# ============== END OF CONFIG ==============

my $port;

sub writeReg
{
    my $regnum;
    my $value;
    {
	no warnings;
	$regnum = @_[0];
	$value = @_[1];
    }
    $port->write("W");
    $port->write(chr($regnum));
    $port->write(chr($value));
}

sub readReg
{
    my $regnum;
    {
	no warnings;
	$regnum = @_[0];
    }
    $port->write("R");
    $port->write(chr($regnum));
    
    my ($count,$saw);
    $count = 0;
    while ($count == 0) {
       ($count,$saw)=$port->read(1);
    }
    return ord($saw);
}

sub runTest
{
    print "TEST STARTED\n";
    my $i = 0;
    my $j = 0;
    for ($i = 0; $i < 32; $i++) {
	&writeReg(0,$i);
	for ($j = 0; $j < 32; $j++) {
	    &writeReg(1,$j);
	    my $int = 0;
	    $int = readReg(1) * 256;
	    $int += readReg(0);
	    
	    if($int != $i * $j) { print "TEST FAILED $i * $j <> $int\n";}
	}
    }
    print "TEST FINISHED\n";
}

$port = Device::SerialPort->new("/dev/ttyS0");

$port->baudrate(115200);
$port->parity("none");
$port->handshake("none");
$port->databits(8);
$port->stopbits(1);
$port->write_settings || undef $port;

my $MySocket=new IO::Socket::INET->new(PeerPort=>$PORTNO,Proto=>'udp',PeerAddr=>'localhost');
$MySocket->send("CONNECT");

my $msg;

while(1)
{
    $MySocket->recv($msg,128);
    print $msg . "\n";
    if($msg eq "FGEN")
    {
	&runTest;
	$MySocket->send("CONTINUE");
    }
    if($msg eq "FSET")
    {
	while($msg ne "###")
	{
	    $MySocket->recv($msg,128);
	    if($msg ne "###"){
		print "FAULT: " . $msg . "\n";
	    }
	}
    }
}

