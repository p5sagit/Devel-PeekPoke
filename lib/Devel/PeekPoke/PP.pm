package # hide hide not just from PAUSE but from everyone - shoo shoo shooooo!
  Devel::PeekPoke::PP;

use strict;
use warnings;

use 5.008001; # because 5.6 doesn't have B::PV::object_2svref

use Carp;
use Config;
use Devel::PeekPoke::Constants qw/PTR_SIZE PTR_PACK_TYPE/;
use B (); # for B::PV

use constant {
  _MAX_ADDR => 'FF' x PTR_SIZE,
  _PERLVERSION => "$]", # we do not support every perl, as we rely on the implementation of SV/SvPV
};

BEGIN {
  # we know we start from 5.8.1
  if ( (_PERLVERSION =~ /^5\.(\d{3})/)[0] % 2 ) {
    die "@{[ __PACKAGE__ ]} does not function on development perl versions (by design)\n";
  }
  elsif (_PERLVERSION < 5.010) {
    constant->import({
      _SV_SIZE => PTR_SIZE + 4 + 4,  # SvANY + 32bit refcnt + 32bit flags
      _XPV_SIZE => PTR_SIZE + $Config{sizesize} + $Config{sizesize}, # PVX ptr + cur + len
      _SVU_OFFSET => 0,
    });
  }
  elsif (_PERLVERSION < 5.016) {
    constant->import({
      _SV_SIZE => PTR_SIZE + 4 + 4 + $Config{ivsize},  # SvANY + 32bit refcnt + 32bit flags + SV_U
      _XPV_SIZE => undef, # it isn't really undefined, we just do not care
      _SVU_OFFSET => PTR_SIZE + 4 + 4,
    });
  }
  else {
    # do not take any chanes with not-yet-released perls - things may change
    die "@{[ __PACKAGE__ ]} does not *yet* support this perl $], please file a bugreport (it is very very easy to fix)\n";
  }
}

sub _pack_address {
  my ($digits) = (defined $_[0] and $_[0] =~ /^(\d+)$/)
    or croak "Invalid address '$_[0]' - expecting an integer";

  my $p = pack(PTR_PACK_TYPE, $_[0]);

  # FIXME - is there a saner way to check for overflows?
  no warnings 'portable'; # hex() with a 64bit value
  croak "Your system does not support addresses larger than 0x@{[ _MAX_ADDR ]}, you supplied $digits"
    if ( $_[0] > hex(_MAX_ADDR) or uc(unpack('H*', $p)) eq _MAX_ADDR );

  return $p;
}

sub peek {
  #my($location, $len_bytes) = @_;
  croak "Peek where and how much?" unless (defined $_[0]) and $_[1];
  unpack "P$_[1]", _pack_address($_[0]);
}

# this implementation is based on (a portably written version of)
# http://www.perlmonks.org/?node_id=379428
# there should be a much simpler way according to Reini Urban, but I
# was not able to make it work: https://gist.github.com/1151345
sub poke {
  my($location, $bytes) = @_;
  croak "Poke where and what?" unless (defined $location) and (defined $bytes);

  # sanity check and properly pack address
  my $addr = _pack_address($location);

  # sanity check is (imho) warranted as described here:
  # http://blogs.perl.org/users/aristotle/2011/08/utf8-flag.html#comment-36499
  if (utf8::is_utf8($bytes) and $bytes  =~ /([^\x00-\x7F])/) {
    croak( ord($1) > 255
      ? "Expecting a byte string, but received characters"
      : "Expecting a byte string, but received what looks like *possible* characters, please utf8_downgrade the input"
    );
  }

  # this should be constant once we pass the regex check above... right?
  my $len = length($bytes);

  # construct a B::PV object, backed by a SV/SvPV to a dummy string length($bytes)
  # long, and substitute $location as the actual string storage
  # we specifically use the same length so we do not have to deal with resizing
  my $dummy = 'X' x $len;
  my $dummy_addr = \$dummy + 0;

  my $ghost_sv_contents = peek($dummy_addr, _SV_SIZE);

  if (_XPV_SIZE) {  # 5.8 xpv stuff
    my $xpv_addr = unpack(PTR_PACK_TYPE, peek($dummy_addr, PTR_SIZE) );
    my $xpv_contents = peek( $xpv_addr, _XPV_SIZE ); # we do not care about cur/len (they will be the same)

    substr( $xpv_contents, 0, PTR_SIZE ) = $addr;  # replace pvx in xpv with the "string buffer" location
    substr( $ghost_sv_contents, 0, PTR_SIZE) = pack ('P', $xpv_contents );  # replace xpv in sv
  }
  else { # new style 5.10+ SVs
    substr( $ghost_sv_contents, _SVU_OFFSET, PTR_SIZE ) = $addr;
  }

  my $ghost_string_ref = bless( \ unpack(
    PTR_PACK_TYPE,
    # it is crucial to create a copy of $sv_contents, and work with a temporary
    # memory location. Otherwise perl memory allocation will kick in and wreak
    # considerable havoc culminating with an inevitable segfault
    do { no warnings 'pack'; pack( 'P', $ghost_sv_contents.'' ) },
  ), 'B::PV' )->object_2svref;

  # now when we write to the newly created "string" we are actually writing
  # to $location
  # note we HAVE to use lvalue substr - a plain assignment will add a \0
  #
  # Also in order to keep threading on perl 5.8.x happy we *have* to perform this
  # in a string eval. I don't have the slightest idea why :)
  eval 'substr($$ghost_string_ref, 0, $len) = $bytes';

  return $len;
}

1;
