#!/usr/bin/perl -w

use JSON::PP;
use URI::Escape;
use Data::Dumper; $Data::Dumper::Indent = 1;
use Getopt::Long;

my $oas_file = 'thymio_motion.json';
my $help = 0;
GetOptions( 'help!' => \$help,
	  );

if ($help) {
  print "Usage: $0 [--help] API.json\n";
  exit(1);
}

my $coder = JSON::PP->new->ascii->pretty->allow_nonref;
open(my $oas_json, '<', $oas_file) or die("Can't open $oas_file: $!");
my $oas = $coder->decode( join('',<$oas_json>) );
#mixin scratchblock(blockdef)
#  object(data="block.html##{blockdef}",type="image/svg+xml")

my $script = '';
my $tbody = '';

foreach my $endpoint (sort grep { /^\/nodes\/(?!\{node\})/ } keys $oas->{paths} ) {
  foreach my $post (grep { defined $_ } sort $oas->{paths}->{$endpoint}->{post}) {
    my $id = $post->{operationId};
    my ($group) = @{ $post->{tags} };
    my $summary = $post->{summary};
    my ($desc1,undef,$desc2) = split /\n/, $post->{description};
    $desc2 =~ s{^Endpoint \S+ }{};
    my $block = $desc1 . " :: extension";
    $block =~ s{\%n}{(0)}g;
    $block =~ s{\%m\.(\S+)}{[$1 v]}g;
    #$block = uri_escape($block);
    $script .= "    " . updateblock($id,$block);
    $tbody .=  "      " . scratchblock($id,$block) . " | $summary<br/>$desc2 | <a href=\"api-doc/#!/$group/$id\">$endpoint</a>\n";
  }
}
foreach my $endpoint (grep { ! /\{\/values\*\}/ } sort grep { /^\/nodes\/(?!\{node\})/ } keys $oas->{paths} ) {
  foreach my $get (grep { defined $_ } sort $oas->{paths}->{$endpoint}->{get}) {
    my $id = $get->{operationId};
    my ($group) = @{ $get->{tags} };
    my $summary = $get->{summary};
    my ($desc1,undef,$desc2) = split /\n/, $get->{description};
    $desc2 =~ s{^Endpoint \S+ }{};
    my $block = "" . $desc1 . " :: extension reporter";
    $block =~ s{\%n}{(0)}g;
    $block =~ s{\%m\.(\S+)}{[$1 v]}g;
    $script .= "    " . updateblock($id,$block);
    $tbody .=  "      " . scratchblock($id,$block) . " | $summary<br/>$desc2 | <a href=\"api-doc/#!/$group/$id\">$endpoint</a>\n";
  }
}

print <<"EOF";
mixin scratchblock(blockdef)
  object(data="block.html##{blockdef}",type="image/svg+xml")

doctype
head
  title Scratch Blocks
  script(src=\"scratchblocks/scratchblocks.js\")
  script(src=\"scratchblocks/translations.js\")
body
  .main
    :markdown
      # Scratch Blocks

      Block  | Summary  | Endpoint 
      ------ | -------- | ---------
$tbody
  script.
$script
EOF

sub updateblock {
  my ($id,$blockdef) = @_;
  return "document.getElementById(\'$id\').innerHTML = scratchblocks(\'$blockdef\');\n";
}

sub scratchblock {
  my ($id,$blockdef) = @_;
  #return "<object data=\"block.html#$blockdef\",type=\"image/svg+xml\" />";
  return "<pre id=\"$id\" class=\"block\"></pre>";
}

