#!/usr/bin/perl -w

use JSON::PP;
use Storable qw(dclone);
use Data::Dumper; $Data::Dumper::Indent = 1;
use Getopt::Long;

my $template = 'minimal.json';
GetOptions( 'template=s' => \$template,
	  );

my $coder = JSON::PP->new->ascii->pretty->allow_nonref;
my $nodes = $coder->decode( join('',<>) );
$nodes = [ $nodes ]
  if (ref($nodes) eq 'HASH');
@unique_names = sort keys { map { $_->{name} => 1 } @$nodes };
@sorted_ids = sort { $a<=>$b } map { $_->{node} } @$nodes;

open(my $template_json, '<', $template) or die("Can't open $template: $!");
my $oas = $coder->decode( join('',<$template_json>) );

$oas->{info}->{title} = 'asebahttp';
$oas->{info}->{description} = join(' ',@unique_names,'REST API','for node'.(scalar(@sorted_ids)>1?'s':''),@sorted_ids);
$oas->{info}->{version} = 'v1';

# Endpoints in minimal:
#   /nodes/{node}/{variableslot}: 
#   /nodes/{node}/{slot}: 
#   /events/{node}: 
#   /events: 
#   /reset: 
#   /nodes: 
#   /nodes/{node}: 

my $ev_slot = $oas->{paths}->{'/nodes/{node}/{slot}'};
my $va_slot = $oas->{paths}->{'/nodes/{node}/{variableslot}'};

foreach my $node (@$nodes) {
  my %events = %{$node->{events}};
  my %variables = %{$node->{namedVariables}};
  # print STDERR "Node ",$node->{node},"\n\tevents ",join(" ",sort keys %events),"\n\tvariables ",join(" ",sort keys %variables),"\n";
  foreach my $ev ( sort keys %events ) {
    my $endpoint = "/nodes/$node->{node}/$ev";
    $oas->{paths}->{$endpoint} ||= dclone($ev_slot);
    $oas->{paths}->{$endpoint}->{post}->{description} =
      join(" ", $ev, ("%n") x $events{$ev})  # first description line is Scratch block definition
      . "\n\n"
      . "Endpoint $ev event slot with $events{$ev} parameters discovered in AESL file";
    $oas->{paths}->{$endpoint}->{post}->{operationId} = "POST_nodes-$node->{node}-$ev";
    $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{minItems} = int($events{$ev});
    $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{maxItems} = int($events{$ev});
    $oas->{paths}->{$endpoint}->{parameters} = [ grep { ($_->{name} ne 'slot') and ($_->{name} ne 'node') }
						 @{$oas->{paths}->{$endpoint}->{parameters}} ];
  }
  foreach my $va ( sort keys %variables ) {
    my $endpoint = "/nodes/$node->{node}/$va";
    $oas->{paths}->{$endpoint} ||= dclone($va_slot);
    $oas->{paths}->{$endpoint}->{get}->{description} =
      join(" ", $va)  # first description line is Scratch reporter definition
      . "\n\n"
      . "Endpoint $va variable slot of size $variables{$va} discovered in AESL file";
    $oas->{paths}->{$endpoint}->{get}->{operationId} = "GET_nodes-$node->{node}-$va";
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{schema}->{minItems} = int($variables{$va});
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{schema}->{maxItems} = int($variables{$va});
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{examples}->{"application/json"} = [ (0) x int($variables{$va})];
    $oas->{paths}->{$endpoint}->{parameters} = [ grep { ($_->{name} ne 'variableslot') and ($_->{name} ne 'node') }
  						 @{$oas->{paths}->{$endpoint}->{parameters}} ];
  }
}
  
$pp = $coder->pretty->encode( $oas );

print $pp, "\n";
