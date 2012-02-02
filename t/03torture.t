use strict;
use warnings;

use Test::More;

use Devel::PeekPoke qw/peek poke peek_address poke_address/;
use Devel::PeekPoke::Constants qw/PTR_SIZE PTR_PACK_TYPE/;

my $str = 'for mutilation and mayhem';
my $len = length($str);
my $str_pv_addr = unpack(PTR_PACK_TYPE, pack('p', $str) );

is( peek($str_pv_addr, $len + 1), $str . "\0", 'peek as expected (with NUL termination)' );

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

done_testing;
