use strict;
use warnings;

# T::M appears to leak, emit the TAP by hand
#use Test::More 'no_plan';

my $tests = 0;
sub is {
  $tests++;
  printf("%s %u - %s\n",
    ( $_[0] eq $_[1] ? 'ok' : 'not ok' ),
    $tests,
    $_[2] || '',
  );
}

use Devel::PeekPoke qw/peek poke peek_address poke_address/;
use Devel::PeekPoke::Constants qw/PTR_SIZE PTR_PACK_TYPE/;

my $str = 'for mutilation and mayhem';
my $len = length($str);
my $str_pv_addr = unpack(PTR_PACK_TYPE, pack('p', $str) );

is( peek($str_pv_addr, $len + 1), $str . "\0", 'peek as expected (with NUL termination)' );

for (1 .. ($ENV{AUTOMATED_TESTING} ? 300 : 20) ) {
  for my $poke_size (2 .. $len) {
    my $replace_chunk = 'a' . ( '0' x ($poke_size-1) );
    for my $poke_start ( 0 .. ($len - $poke_size) ) {
      $replace_chunk++;

      my $expecting = $str;
      substr($expecting, $poke_start, $poke_size, $replace_chunk);

      poke($str_pv_addr+$poke_start, $replace_chunk);
      is($str, $expecting, 'String matches expectation after poke');
    }
  }
}

if ($ENV{AUTOMATED_TESTING}) {
  my $vsz;
  if (-f "/proc/$$/stat") {
    my $proc_stat = do { local (@ARGV, $/) = "/proc/$$/stat"; <> };
    ($vsz) = map { $_ / 1024 }
      (split (/\s+/, $proc_stat))[-22];  # go backwards because the %s of the procname can contain anything
  }

  printf STDERR "#\n# VSIZE:%dKiB\n", $vsz
    if $vsz;
}

print "1..$tests\n";
