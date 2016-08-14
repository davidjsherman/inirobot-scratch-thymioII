#!/usr/bin/perl -w

use XML::XPath;
use XML::XPath::XMLParser;
use JSON::PP;
use Storable qw(dclone);
use Data::Dumper; $Data::Dumper::Indent = 1;
use Getopt::Long;

my $template = 'minimal.json';
my $use_names = 0;
my $help = 0;
GetOptions( 'template=s' => \$template,
	    'usenames!' => \$use_names,
	    'help!' => \$help,
	  );

if ($help) {
  print "Usage: $0 [--template=TEMPLATE.json] [--help] PROGRAM.aesl\n";
  exit(1);
}
(my $aesl_file = shift) ||= 'vmcode.aesl';

my $coder = JSON::PP->new->ascii->pretty->allow_nonref;

my $xp = XML::XPath->new(filename => $aesl_file);
my $eventset = $xp->find('/network/event');
my $constantset = $xp->find('/network/constant');
my $nodeset = $xp->find('/network/node');

my %events = get_events($eventset);
my %constants = get_constants($constantset);

my $nodes = get_nodes($nodeset);
@unique_names = sort keys { map { $_->{name} => 1 } @$nodes };
@sorted_ids = sort { $a<=>$b } map { $_->{node} } @$nodes;

my $oas = hardcoded_template();
if (open(my $template_json, '<', $template)) {
  $oas = $coder->decode( join('',<$template_json>) );
}

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
  my %variables = %{$node->{namedVariables}};
  my %handledEvents = %{$node->{handledEvents}};
  my $route_name = ($use_names ? $node->{name} : $node->{node});
  # print STDERR "Node ",$route_name,"\n\tevents ",join(" ",sort keys %events),"\n\tvariables ",join(" ",sort keys %variables),"\n";
  foreach my $ev ( sort keys %handledEvents ) {
    my $endpoint = "/nodes/$route_name/$ev";
    if (!defined($events{$ev}) or !$handledEvents{$ev}->{brief}) {
      #warn("skipping unknown or undocumented event $ev\n");
      next;
    }
    (my $brief = $handledEvents{$ev}->{brief}) ||= join(" ", $ev, ("%n") x $events{$ev});
    # event slots can be updated
    $oas->{paths}->{$endpoint} ||= dclone($ev_slot);
    $oas->{paths}->{$endpoint}->{post}->{summary} = "update slot $ev";
    $oas->{paths}->{$endpoint}->{post}->{tags} = [ $handledEvents{$ev}->{group} ]
      if (defined $handledEvents{$ev}->{group});
    $oas->{paths}->{$endpoint}->{post}->{description} =
      $brief  # first description line is Scratch block definition
      . "\n\n"
      . "Endpoint $ev event slot with $events{$ev} parameters discovered in AESL file";
    $oas->{paths}->{$endpoint}->{post}->{operationId} = "POST_nodes-$route_name-$ev";
    $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{minItems} = int($events{$ev});
    $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{maxItems} = int($events{$ev});
    $oas->{paths}->{$endpoint}->{parameters} = [ grep { ($_->{name} ne 'slot') and ($_->{name} ne 'node') }
						 @{$oas->{paths}->{$endpoint}->{parameters}} ];
  }
  foreach my $va ( sort keys %variables ) {
    # print STDERR "namedVariable $va ",Dumper($variables{$va});
    my $endpoint = "/nodes/$route_name/$va";
    # variable slots can be read
    $oas->{paths}->{$endpoint} ||= dclone($va_slot);
    $oas->{paths}->{$endpoint}->{get}->{summary} = "read slot $va";
    $oas->{paths}->{$endpoint}->{get}->{tags} = [ $variables{$va}->{group} ]
      if (defined $variables{$va}->{group});
    $oas->{paths}->{$endpoint}->{get}->{description} =
      join(" ", $va)  # first description line is Scratch reporter definition
      . "\n\n"
      . "Endpoint $va variable slot of size $variables{$va}->{size} discovered in AESL file";
    $oas->{paths}->{$endpoint}->{get}->{operationId} = "GET_nodes-$route_name-$va";
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{schema}->{minItems} = int($variables{$va}->{size});
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{schema}->{maxItems} = int($variables{$va}->{size});
    $oas->{paths}->{$endpoint}->{get}->{responses}->{"200"}->{examples}->{"application/json"} = [ (0) x int($variables{$va}->{size})];
    $oas->{paths}->{$endpoint}->{parameters} = [ grep { ($_->{name} ne 'variableslot') and ($_->{name} ne 'node') }
  						 @{$oas->{paths}->{$endpoint}->{parameters}} ];
    # variable slots can also be updated unless marked read-only
    if ($variables{$va}->{direction} =~ /in/) {
      # REST update by POST
      $oas->{paths}->{$endpoint}->{post} ||= dclone($ev_slot->{post});
      my $brief = join(" ", $va, ("%n") x int($variables{$va}->{size}));
      $oas->{paths}->{$endpoint}->{post}->{summary} = "update slot $va";
      $oas->{paths}->{$endpoint}->{post}->{tags} = [ $variables{$va}->{group} ]
	if (defined $variables{$va}->{group});
      $oas->{paths}->{$endpoint}->{post}->{description} =
	$brief  # first description line is Scratch block definition
	. "\n\n"
	. "Endpoint $va variable slot with $variables{$va}->{size} parameters discovered in AESL file";
      $oas->{paths}->{$endpoint}->{post}->{operationId} = "POST_nodes-$route_name-$va";
      $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{minItems} = int($variables{$va}->{size});
      $oas->{paths}->{$endpoint}->{post}->{parameters}->[0]->{schema}->{maxItems} = int($variables{$va}->{size});
      $oas->{paths}->{$endpoint}->{parameters} = [ grep { ($_->{name} ne 'slot') and ($_->{name} ne 'node') }
						   @{$oas->{paths}->{$endpoint}->{parameters}} ];
      # nonconrfoming REST update by GET
      my $get_endpoint = $endpoint . '{/values*}'; # composite path segments, slash-prefixed
      $oas->{paths}->{$get_endpoint} ||= dclone($va_slot);
      $oas->{paths}->{$get_endpoint}->{get}->{summary} = "update slot $va";
      $oas->{paths}->{$get_endpoint}->{get}->{tags} = [ $variables{$va}->{group} ]
	if (defined $variables{$va}->{group});
      $oas->{paths}->{$get_endpoint}->{get}->{description} =
	$brief  # first description line is Scratch reporter definition
	. "\n\n"
	. "Endpoint $va variable slot with $variables{$va}->{size} parameters discovered in AESL file";
      $oas->{paths}->{$get_endpoint}->{get}->{operationId} = "GET_nodes-$route_name-$va-values";
      $oas->{paths}->{$get_endpoint}->{get}->{responses} = $oas->{paths}->{$endpoint}->{post}->{responses};
      $oas->{paths}->{$get_endpoint}->{parameters} = [ grep { ($_->{name} ne 'variableslot') and ($_->{name} ne 'node') }
						       @{$oas->{paths}->{$get_endpoint}->{parameters}},
						       { "name"=>"values", "in"=>"path", "required"=>"false", "type"=>"string" } ];
    }
  }

  # remove generic routes if specific ones were found
  delete $oas->{paths}->{'/nodes/{node}/{slot}'} if (keys %handledEvents > 1);
  delete $oas->{paths}->{'/nodes/{node}/{variableslot}'} if (keys %variables > 1);
}
  
$pp = $coder->pretty->encode( $oas );

print $pp, "\n";

sub hardcoded_template {
  my $hardcoded = <<'EOF';
{
    "swagger": "2.0",
    "schemes": [
        "http"
    ],
    "host": "localhost:3001",
    "info": {
        "version": "v1",
        "title": "minimal",
        "description": "minimal REST API for asebahttp"
    },
    "paths": {
        "/nodes/{node}/{variableslot}": {
            "parameters": [
                {
                    "name": "node",
                    "in": "path",
                    "required": true,
                    "type": "string"
                },
                {
                    "name": "variableslot",
                    "in": "path",
                    "required": true,
                    "type": "string"
                }
            ],
            "get": {
                "tags": [
                    "Nodes"
                ],
                "summary": "read slot",
                "description": "read values from variable slot",
                "operationId": "GET_nodes-node-variableslot",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [],
                "responses": {
                    "200": {
                        "description": "variable slot",
                        "schema": {
                            "type": "array",
                            "items": {
                                "type": "integer"
                            }
                        }
                    },
                    "404": {
                        "description": "no such variable slot",
                        "schema": {
                            "type": "string"
                        }
                    }
                }
            }
        },
        "/nodes/{node}/{slot}": {
            "parameters": [
                {
                    "name": "node",
                    "in": "path",
                    "required": true,
                    "type": "string"
                },
                {
                    "name": "slot",
                    "in": "path",
                    "required": true,
                    "type": "string"
                }
            ],
            "post": {
                "tags": [
                    "Nodes"
                ],
                "summary": "update slot",
                "description": "assign to variable slot or emit event with given payload",
                "operationId": "POST_nodes-node-slot",
                "consumes": [
                    "application/json"
                ],
                "produces": [
                    "application/json"
                ],
                "parameters": [
                    {
                        "name": "body",
                        "in": "body",
                        "schema": {
                            "type": "array",
                            "items": {
                                "type": "integer"
                            }
                        }
                    }
                ],
                "responses": {
                    "204": {
                        "description": "slot update accepted",
                        "schema": {
                            "type": "null"
                        }
                    },
                    "404": {
                        "description": "no such slot",
                        "schema": {
                            "type": "string"
                        }
                    }
                }
            }
        },
        "/events/{node}": {
            "parameters": [
                {
                    "name": "node",
                    "in": "path",
                    "required": true,
                    "type": "string"
                }
            ],
            "get": {
                "tags": [
                    "Events"
                ],
                "summary": "event stream",
                "description": "subscribe to server-sent event streamfor given node",
                "operationId": "GET_events-node",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [
                    {
                        "$ref": "#/parameters/trait:serverSentEventStream:todo"
                    }
                ],
                "responses": {
                    "200": {
                        "$ref": "#/responses/trait:serverSentEventStream:200"
                    },
                    "404": {
                        "description": "no such node, event stream not subscribed",
                        "schema": {
                            "type": "string"
                        }
                    }
                }
            }
        },
        "/events": {
            "parameters": [],
            "get": {
                "tags": [
                    "Events"
                ],
                "summary": "event stream",
                "description": "subscribe to server-sent event stream",
                "operationId": "GET_events",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [
                    {
                        "$ref": "#/parameters/trait:serverSentEventStream:todo"
                    }
                ],
                "responses": {
                    "200": {
                        "$ref": "#/responses/trait:serverSentEventStream:200"
                    },
                    "default": {
                        "description": "event stream not subscribed"
                    }
                }
            }
        },
        "/reset": {
            "parameters": [],
            "get": {
                "tags": [
                    "Reset"
                ],
                "summary": "reset nodes",
                "description": "send reset request to all nodes",
                "operationId": "GET_reset",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [],
                "responses": {
                    "204": {
                        "description": "reset request sent"
                    }
                }
            }
        },
        "/nodes": {
            "parameters": [],
            "get": {
                "tags": [
                    "Nodes"
                ],
                "summary": "list nodes",
                "description": "list all known nodes",
                "operationId": "GET_nodes",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [],
                "responses": {
                    "200": {
                        "description": "node list returned",
                        "schema": {
                            "type": "array",
                            "items": {
                                "$ref": "#/definitions/nodeshort"
                            }
                        },
                        "examples": {
                            "application/json": [
                                {
                                    "node": 1,
                                    "name": "thymio-II",
                                    "protocolVersion": 5,
                                    "aeslId": 1
                                },
                                {
                                    "node": 21,
                                    "name": "thymio-II",
                                    "protocolVersion": 5,
                                    "aeslId": 2
                                }
                            ]
                        }
                    }
                }
            }
        },
        "/nodes/{node}": {
            "parameters": [
                {
                    "name": "node",
                    "in": "path",
                    "required": true,
                    "type": "string"
                }
            ],
            "get": {
                "tags": [
                    "Nodes"
                ],
                "summary": "details of one node",
                "description": "return detailed description of one node",
                "operationId": "GET_nodes-node",
                "consumes": [],
                "produces": [
                    "application/json"
                ],
                "parameters": [],
                "responses": {
                    "200": {
                        "description": "node details returned",
                        "schema": {
                            "$ref": "#/definitions/nodedescription"
                        },
                        "examples": {
                            "application/json": {
                                "node": 1,
                                "name": "thymio-II",
                                "protocolVersion": 5,
                                "aeslId": 1,
                                "bytecodeSize": 1534,
                                "variablesSize": 585,
                                "stackSize": 32,
                                "namedVariables": {
                                    "_fwversion": 2,
                                    "_id": 1,
                                    "_productId": 1,
                                    "acc": 3,
                                    "button.backward": 1,
                                    "button.center": 1,
                                    "button.forward": 1,
                                    "button.left": 1,
                                    "button.right": 1,
                                    "event.args": 32,
                                    "event.source": 1,
                                    "mic.intensity": 1,
                                    "mic.threshold": 1,
                                    "motor.left.pwm": 1,
                                    "motor.left.speed": 1,
                                    "motor.left.target": 1,
                                    "motor.right.pwm": 1,
                                    "motor.right.speed": 1,
                                    "motor.right.target": 1,
                                    "prox.comm.rx": 1,
                                    "prox.comm.tx": 1,
                                    "prox.ground.ambiant": 2,
                                    "prox.ground.delta": 2,
                                    "prox.ground.reflected": 2,
                                    "prox.horizontal": 7,
                                    "rc5.address": 1,
                                    "rc5.command": 1,
                                    "temperature": 1,
                                    "timer.period": 2
                                },
                                "localEvents": {
                                    "button.backward": "Backward button status changed",
                                    "button.left": "Left button status changed",
                                    "button.center": "Center button status changed",
                                    "button.forward": "Forward button status changed",
                                    "button.right": "Right button status changed",
                                    "buttons": "Buttons values updated",
                                    "prox": "Proximity values updated",
                                    "prox.comm": "Data received on the proximity communication",
                                    "tap": "A tap is detected",
                                    "acc": "Accelerometer values updated",
                                    "mic": "Fired when microphone intensity is above threshold",
                                    "sound.finished": "Fired when the playback of a user initiated sound is finished",
                                    "temperature": "Temperature value updated",
                                    "rc5": "RC5 message received",
                                    "motor": "Motor timer",
                                    "timer0": "Timer 0",
                                    "timer1": "Timer 1"
                                },
                                "constants": {},
                                "events": {}
                            }
                        }
                    },
                    "404": {
                        "description": "no such node",
                        "schema": {
                            "type": "string"
                        }
                    }
                }
            }
        }
    },
    "definitions": {
        "nodeshort": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "node": {
                        "type": "integer"
                    },
                    "name": {
                        "type": "string"
                    },
                    "protocolVersion": {
                        "type": "integer"
                    },
                    "aeslId": {
                        "type": "integer"
                    }
                },
                "required": [
                    "node",
                    "name",
                    "protocolVersion",
                    "aeslId"
                ]
            }
        },
        "nodedescription": {
            "type": "object",
            "properties": {
                "node": {
                    "type": "integer"
                },
                "name": {
                    "type": "string"
                },
                "protocolVersion": {
                    "type": "integer"
                },
                "aeslId": {
                    "type": "integer"
                },
                "bytecodeSize": {
                    "type": "integer"
                },
                "variablesSize": {
                    "type": "integer"
                },
                "stackSize": {
                    "type": "integer"
                },
                "namedVariables": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "integer"
                        }
                    }
                },
                "localEvents": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string"
                        }
                    }
                },
                "constants": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "integer"
                        }
                    }
                },
                "events": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "integer"
                        }
                    }
                }
            },
            "required": [
                "node",
                "name",
                "protocolVersion",
                "aeslId",
                "bytecodeSize",
                "variablesSize",
                "stackSize",
                "namedVariables",
                "localEvents",
                "constants",
                "events"
            ]
        }
    },
    "parameters": {
        "trait:serverSentEventStream:todo": {
            "name": "todo",
            "in": "query",
            "required": false,
            "type": "integer"
        }
    },
    "responses": {
        "trait:serverSentEventStream:200": {
            "description": "stream of server-sent events",
            "schema": {
                "type": "string"
            }
        }
    }
}
EOF
  return $coder->decode($hardcoded);
}

sub get_events {
  my $eventset = shift;
  my %these_events;
  foreach my $ev ($eventset->get_nodelist) {
    my $size = $ev->getAttribute('size');
    my $name = $ev->getAttribute('name') or next;
    $these_events{$name} = $size;
  }
  return %these_events;
}

sub get_constants {
  my $constantset = shift;
  my %these_constants;
  foreach my $co ($constantset->get_nodelist) {
    my $value = $co->getAttribute('value') or next;
    my $name = $co->getAttribute('name') or next;
    $these_constants{$name} = $value;
  }
  return %these_constants;
}

sub get_nodes {
  my $nodeset = shift;
  my $these_nodes = [];
  foreach my $no ($nodeset->get_nodelist) {
    my $nodeid = $no->getAttribute('nodeId') or next;
    my $name = $no->getAttribute('name') or next;
    my $node = { 'node' => $nodeid, 'name' => $name };

    my %std_vars;
    %std_vars = ("acc"=>['3','out'],
		 "button.backward"=>['1','out'],
		 "button.center"=>['1','out'],
		 "button.forward"=>['1','out'],
		 "button.left"=>['1','out'],
		 "button.right"=>['1','out'],
		 "event.args"=>['32','out'],
		 "event.source"=>['1','out'],
		 "mic.intensity"=>['1','out'],
		 "mic.threshold"=>['1','out'],
		 "motor.left.pwm"=>['1','out'],
		 "motor.left.speed"=>['1','out'],
		 "motor.left.target"=>['1','in,out'],
		 "motor.right.pwm"=>['1','out'],
		 "motor.right.speed"=>['1','out'],
		 "motor.right.target"=>['1','in,out'],
		 "prox.comm.rx"=>['1','in,out'],
		 "prox.comm.tx"=>['1','in,out'],
		 "prox.ground.ambiant"=>['2','out'],
		 "prox.ground.delta"=>['2','out'],
		 "prox.ground.reflected"=>['2','out'],
		 "prox.horizontal"=>['7','out'],
		 "rc5.address"=>['1','out'],
		 "rc5.command"=>['1','out'],
		 "temperature"=>['1','out'],
		 "timer.period"=>['2','in,out'])
      if ($name =~ /^thymio/i);    
    %std_vars = ("args"=>['32','out'],
		 "id"=>['1','in,out'],
		 "source"=>['1','in,out'])
      if ($name =~ /^dummynode/i);
    
    my $program = XML::XPath::XMLParser::as_string($no);
    # while ($program =~ m{^\s* var \s+ ([[:alnum:]\_\.]+) (?:\[(.*?)\])? }gsmx) {
    #   my $var = $1;
    #   (my $size = $2) ||= '1';
    #   $size = $constants{$size} if (defined $constants{$size});
    #   $node->{'namedVariables'}->{$var} = $size;
    # }
    foreach (keys %std_vars) {
      $node->{'namedVariables'}->{$_}->{size} = $std_vars{$_}->[0];
      $node->{'namedVariables'}->{$_}->{direction} = $std_vars{$_}->[1];
      $node->{'namedVariables'}->{$_}->{group} = 'Builtin';
    }
    
    my $brief = '';
    my @param = ();
    my $defgroup = '';
    foreach my $line (split /\n/, $program) {
      if ($line =~ m{^\s* \#\#\! \s* \@brief \s+ (.+) }gsmx) {
	$brief = $1;
	$brief =~ s{\\%}{%}g;
	@param = ();
	# print STDERR "found brief $brief in ",$line,"\n";
      }
      if ($line =~ m{^\s* \#\#\! \s* \@param \s+ ([[:alnum:]\_\.]+) .*? }gsmx) {
	push @param, $1;
	# print STDERR "found param $1 in ",$line,"\n";
      }
      if ($line =~ m{^\s* \#\#\! \s* \@defgroup \s+ ([[:alnum:]\_\.]+) .*? }gsmx) {
	$defgroup = $1;
	# print STDERR "found defgroup $1 in ",$line,"\n";
      }
      if ($line =~ m{^\s* \#\#\! \s* \@\} .*? }gsmx) {
	# print STDERR "stop defgroup in ",$line,"\n";
	$defgroup = '';
      }
      if ($line =~ m{^\s* onevent \s+ ([[:alnum:]\_\.]+) }gsmx) {
	my $name = $1;
	$brief ||= join(' ', $name, ('%n') x scalar(@param));
	$node->{'handledEvents'}->{$name} = { 'brief'=>$brief, 'param'=>[@param], 'size'=>scalar(@param) };
	$node->{'handledEvents'}->{$name}->{group} = $defgroup if $defgroup;
	# print STDERR "handledEvent $name group $defgroup brief $brief\n";
	$brief = '';
	@param = ();
      }
      if ($line =~  m{^\s* var \s+ ([[:alnum:]\_\.]+) (?:\[(.*?)\])? (?: .*?\#\#\!\&lt;\s* \[(\w+)\])? }gsmx) {
	my $var = $1;
	(my $size = $2) ||= '1';
	(my $direction = $3) ||= 'in,out';
	$size = $constants{$size} if (defined $constants{$size});
	$node->{'namedVariables'}->{$var} = { 'size'=>$size };
	$node->{'namedVariables'}->{$var}->{group} = $defgroup if $defgroup;
	$node->{'namedVariables'}->{$var}->{direction} = $direction;
	# print STDERR "namedVariable $var ",Dumper($node->{'namedVariables'}->{$var});
	# print STDERR "namedVariable $var size $size group $defgroup\n";
      }
    }
    
    push @$these_nodes, $node;
  }
  return $these_nodes;
}
