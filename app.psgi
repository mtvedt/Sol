#!/usr/bin/perl
 
 use aliec2ws;
  my $application = aliec2ws2->new;
  my $app = sub { $application->run_psgi(@_) };
