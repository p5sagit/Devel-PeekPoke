use strict;
use warnings;

use Test::More;
use Devel::PeekPoke::Constants qw/PTR_SIZE PTR_PACK_TYPE BIG_ENDIAN/;

diag("\nPerl: $]\n");
diag(sprintf "%s: %s\n", $_, __PACKAGE__->$_ ) for (qw/BIG_ENDIAN PTR_SIZE PTR_PACK_TYPE/);

ok('this is not a test, it just serves to diag() out what this system is using, for the curious (me)');
done_testing;
