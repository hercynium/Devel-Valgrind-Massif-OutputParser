use strict;
use warnings;
package Devel::Valgrind::Massif::OutputParser;

# ABSTRACT: Parse the output from massif just like msparser.py

use autodie;

=method new()

While you can call the other methods as class methods, this is here to make OO
folk happier, and to somewhat appease the "dammit these package names are too 
damned long" people, (like me) too.

  my $mp = Devel::Valgrind::Massif::OutputParser->new();

=cut

sub new { return bless {}, shift }

=method parse_file($file_name)

A convenience method, provided because msparser.py has it, too.

$file_name is a string that is the path to an output file created by running massif.

The output is the same data structure that would be returned from ->parse().

=cut

sub parse_file {
  my ($self, $file) = @_;
  open my $fh, '<', $file;
  return $self->parse($fh);
}

=method parse($fh)

$fh is a readable file handle, or something that can behave like one.

The main method for this package, it reads the output data from massif through
the given file handle and returns a perl data structure that mirrors the one
output by msparser.py in python.

=cut

sub parse {
  my ($self, $fh) = @_;
  return $self->_do_parse($fh);
}

sub _do_parse {
  my ($self, $fh) = @_;

  my %mdata;
  my $cur_snapshot;
  my $heap_tree_depth;

  while (defined(my $line = readline $fh)) {

    next if $line =~ /^\s*#/; # comment line

    if ($line =~ /^snapshot\s*=\s*(.*)/ ) {
      $cur_snapshot = $1;
      $mdata{snapshots}[$cur_snapshot]{heap_tree} = undef;
      next;
    }

    if ($line =~ /^(\w+)\s*=\s*(.*)/ ) {
      unless ( defined $cur_snapshot) {
        $mdata{$1} = $2;
        next;
      }

      if ($1 eq "heap_tree") {
        if (lc($2) eq "detailed") {
          push @{ $mdata{detailed_snapshots_index} ||= [] }, $cur_snapshot;
        }

        if (lc($2) eq "peak") {
          $mdata{peak_snapshot_index} = $cur_snapshot;
        }
        next;
      }

      $mdata{snapshots}[$cur_snapshot]{$1} = $2;
      next;
    }

    if ($line =~ /^\s*(\w+)\s*:\s*(.*)/ ) {
      unless ( defined $cur_snapshot) {
        $mdata{$1} = $2;
        next;
      }

      # we have a heap-tree entry... time to parse that monstrosity
      $mdata{snapshots}[$cur_snapshot]{heap_tree} =
        _build_heap_tree($fh, _make_heap_node($line), 0);
      next;
    }
  }

  return \%mdata;
}



sub _make_heap_node {
  my ($line) = @_;

  chomp $line;

  my ($num_children, $bytes, $details) =
    ($line =~ /^\s* n(\d+): \s*(\d+) \s+(.*)/x);

  # if the regex didn't match...
  return unless defined $num_children;

  my ($addr, $func, $file, $line_num) =
    ($details =~ /(0x[0-9A-F]+): ([^\s]+) \((?:in)? (.*?)(?:\:(\d+))?\)/);

  # save the info
  return {
    num_children => $num_children,
    #raw_line     => $line,
    children     => [],
    nbytes       => $bytes,
    details      => (!$addr ? undef : {
      address  => $addr,
      function => $func,
      file     => $file,
      line     => $line_num,
    }),
  };
}

sub _build_heap_tree {
  my ($fh, $parent) = @_;

  my @siblings;
  for my $sib_num ( 0 .. $parent->{num_children} - 1 ) {

    defined(my $line = readline $fh) or return;
    my $sib = _make_heap_node($line);
    return unless $sib;
    push @{ $parent->{children} }, $sib;

    if ( $sib->{num_children} ) {
      _build_heap_tree($fh, $sib);
      next;
    }
  }
  return $parent;
}

1;
__END__

=head1 SYNOPSIS

  use Devel::Valgrind::Massif::OutputParser;
  my $data;

  # so, you could do this:
  my $data0 = Devel::Valgrind::Massif::OutputParser->parse_file($some_file);
  my $data1 = Devel::Valgrind::Massif::OutputParser->parse($some_fh);

  # or you could do this:
  my $mp = Devel::Valgrind::Massif::OutputParser->new();
  my $data2 = $mp->parse_file($some_file);
  my $data3 = $mp->parse($some_fh);


