#!/usr/bin/perl -w

# Messy little program to run doxygen on an Aesl file and generate XML, HTML, and LaTeX documentation.
# Comments in Aesl files must follow doxygen syntax, with a ##! prefix.
#
# Normal usages:
#   aesl-doxygen.perl --run
#   aesl-doxygen.perl --aesl FILE.aesl

use Getopt::Long;
my $generate = 0;
my $run = 0;
my $aesl = '';
my $verbose = 0;
my $help = 0;
GetOptions( "generate|g!" => \$generate,
	    "run|r!" => \$run,
	    "aesl|a=s" => \$aesl,
	    "verbose|v!" => \$verbose,
	    "help|h!" => \$help );
if ($help) {
  print << "EOF";
Usage: $0 [--generate|-g] [--run|-r] [--aesl|-a=AESL_FILE] [--verbose|-v] [--help|-h]
	--generate|-g		Generate Doxyfile
	--run|-r		Run Doxygen directly
	--aesl|-a=AESL_FILE	Specify which AESL file to document
	--verbose|-v		Verbose flag
	--help|-h		Show this help
EOF
  exit;
}
if ($generate) {
  print Doxyfile();
  exit;
}
elsif ($run or $aesl) {
  run_doxygen($aesl);
  exit;
}

(my $filename = shift) ||= '-';
open(my $input, '<', $filename) or die("Can't open $filename: $!");
my $p = join('',<$input>);
close $input;

my ($head,$programs,$tail) = ($p =~ m{(.*?)(<!--node .*?-->\n<node.*?>.*</node>)(.*)}sm);
my @nodes = ($programs =~ m{(<!--node .*?-->\n<node.*?>.*?</node>)}smg);

# envelope
$head =~ s{<!DOCTYPE aesl-source>\n<network>}{\n}smg;
$head =~ s{\#\#!(.*?)$}{//!$1}smg;
$tail =~ s{</node>}{}smg;
$tail =~ s{</network>}{}smg;

# events
my @events = ($head =~ m{<event size="(?:\d+)" name="(.*?)"/>}smg);
$head =~ s{\n\n<!--list of global events-->}{\n//! \@defgroup aesl_events Global Events\n//! \@\{}smg;
$head =~ s{<event size="(\d+)" name="(.*?)"/>}{$2(integer[$1]); //!< Global event $2}smg;

# constants
# note line numbers for constants will be off by one
my @constants = ($head =~ m{<constant value="(?:\d+)" name="(.*?)"/>}smg);
$head =~ s{\n\n<!--list of constants-->}{\n//! \@\}\n//! \@defgroup aesl_constants Constants\n//! \@\{}smg;
$head =~ s{<constant value="(\d+)" name="(.*?)"/>}{integer $2 = $1; //!< Constant $2}smg;

# keywords
$head =~ s{\n\n<!--show keywords state-->}{\n//! \@\}}smg;
$head =~ s{<keywords.*?/>}{}smg;

# head done
print $head;

# nodes
# program lines
foreach my $node (@nodes) {
  my ($nodecomment,$nodeid,$nodename,$program) =
    ($node =~ m{<!--node (.*?)-->\n<node nodeId="(.*?)" name="(.*?)">(.*)</node>}sm);
  $nodename =~ s{-}{_dash_}g;
  $program =~ s{&lt;}{<}smg;

  my $class = $nodename .'::node_'. $nodeid;
  my $output = "class $class {\n"; # for <!-- node --> and <node>
  my @params = ();
  
  foreach my $line (split /\n/, $program) {

    push @params, ($line =~ m{\#\#\!\s*\@param\s+(\w+)});
    
    ($line =~ s{^\s*var\s+ ([[:alnum:]\_\.]+)	# var name
		\[(.*?)\]			# [dimensions]
		(?: \s* = \s* \[([^#\]]*)\]?)?	# = [initializer], possibly truncated
		.*? (?=\#)? 			# anything up to '#' if present
	       }{"integer[$2] ".variableize($1,$class).(defined $3 ? " = \{$3\}" : "").";"}gxe > 0)
    or
    ($line =~ s{^\s*var\s+ ([[:alnum:]\_\.]+)
		(?: \s* = \s* ([^#\] ]+))?
		(?=\#)?
	       }{"integer[1] ".variableize($1,$class).(defined $2 ? " = \{$2\}" : "").";"}gxe > 0)
    or
    ($line =~ s{^\s*sub\s+ ([[:alnum:]\_\.]+)}{functionize($1,$class,@params)}gxe and not @params=())
    or
    ($line =~ s{^\s*onevent\s+ ([[:alnum:]\_\.]+)}{functionize($1,$class,@params)}gxe and not @params=())
    or
    ($line =~ s{.*?\#(?!\#\!)}{//})
    or
    ($line = "");

    $line =~ s{\#\#\!(.*?)}{//!$1}smg;
    $output .= "$line\n";
  }
  $output .= "\n}; //!< class for $nodename id $nodeid\n"; # </node>, end class $class
  print $output;
}



# tail done
print $tail;


sub variableize {
  my $name = shift;
  (my $class = shift) ||= '';
  $name =~ s{\.}{_dot_}g;
  # return ($class ? $class.'::' : '') . $name;
  return $name;
}

sub functionize {
  my ($name,$class,@args) = @_;
  return variableize($name,$class) .
    '('.join(',',map { "integer $_" } @args).')' . '{}';
}

sub Doxyfile {
  my $aesl_file = shift;
  $aesl_file = $aesl unless ($aesl_file and -s $aesl_file);
  return <<"EOF";
    PROJECT_NAME           = "Aesl Program"
    EXTENSION_MAPPING      = aesl=C++
    INPUT_FILTER           = ./aesl-doxygen.perl
    EXTRACT_PRIVATE        = YES
    HIDE_SCOPE_NAMES       = YES
    USE_MATHJAX            = YES
    FILE_PATTERNS          = *.aesl
    INPUT                  = $aesl_file
    MATHJAX_RELPATH        = "https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-MML-AM_CHTML"
    GENERATE_HTML          = YES
    GENERATE_XML           = YES
    XML_PROGRAMLISTING     = NO
EOF
}

sub run_doxygen {
  open(my $dox, '|-', 'doxygen -') or die("Can't pipe to doxygen: $!");
  print $dox Doxyfile();
  close($dox);
  system('find xml html -name \*.\*ml -print0 | xargs -0 perl -pi -e \'s{_dot_}{.}g;s{_dash_}{-}g\'');
  system('find xml html -name \*_dash_\*.\*ml -print | perl -n -e \'chomp;$o=$_;$_=~s{_dash_}{-}g;print "mv \"$o\" \"$_\"\n"\' | bash');
}

