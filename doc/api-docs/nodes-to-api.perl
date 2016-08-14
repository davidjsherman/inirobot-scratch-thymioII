#!/usr/bin/perl -w

use JSON::PP;
use Storable qw(dclone);
use Data::Dumper; $Data::Dumper::Indent = 1;
use Getopt::Long;

my $template = 'minimal.json';
my $help = 0;
GetOptions( 'template=s' => \$template,
	    'help!' => \$help,
	  );

if ($help) {
  print "Usage: $0 [--template=minimal.json] [--help]\n";
  exit(1);
}

my $coder = JSON::PP->new->ascii->pretty->allow_nonref;
my $nodes = $coder->decode( join('',<>) );
$nodes = [ $nodes ]
  if (ref($nodes) eq 'HASH');
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
