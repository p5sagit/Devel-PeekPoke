package # hide hide not just from PAUSE but from everyone - shoo shoo shooooo!
  Devel::PeekPoke::PP;

use strict;
use warnings;

use 5.008001; # because 5.6 doesn't have B::PV::object_2svref

use Carp;
use Config;
use Devel::PeekPoke::Constants qw/PTR_SIZE PTR_PACK_TYPE/;
use B (); # for B::PV

# we do not support every perl, as we rely on the implementation of SV/SvPV
BEGIN { eval "sub __PERLVER () { $] }" };

my ($svsize, $svu_offset, $xpv_size);
# we know we start from 5.8.1
if ( (__PERLVER =~ /^5\.(\d{3})/)[0] % 2 ) {
  die "@{[ __PACKAGE__ ]} does not function on development perl versions (by design)\n";
}
elsif (__PERLVER < 5.010) {
  $svsize = PTR_SIZE + 4 + 4; # SvANY + 32bit refcnt + 32bit flags
  $xpv_size = PTR_SIZE + $Config{sizesize} + $Config{sizesize}; # PVX ptr + cur + len
}
elsif (__PERLVER < 5.016) {
  $svsize = PTR_SIZE + 4 + 4 + $Config{ivsize}; # SvANY + 32bit refcnt + 32bit flags + SV_U
  $svu_offset = PTR_SIZE + 4 + 4;
}
else {
  # do not take any chanes with not-yet-released perls - things may change
  die "@{[ __PACKAGE__ ]} does not *yet* support this perl $], please file a bugreport (it is very very easy to fix)\n";
}

my $max_addr = ('FF' x PTR_SIZE);

sub _pack_address {
  my ($digits) = (defined $_[0] and $_[0] =~ /^(\d+)$/)
    or croak "Invalid address '$_[0]' - expecting an integer";

  my $p = pack(PTR_PACK_TYPE, $_[0]);

  # FIXME - is there a saner way to check for overflows?
  no warnings 'portable'; # hex() with a 64bit value
  croak "Your system does not support addresses larger than 0x$max_addr, you supplied $_[0]"
    if ( $_[0] > hex($max_addr) or uc(unpack('H*', $p)) eq $max_addr );

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

  # construct a B::PV object, backed by a SV/SvPV to a dummy string lenth($bytes)
  # long, and subtitute $location as the actual string storage
  # we specifically use the same length so we do not have to deal with resizing
  my $sv_ref = \( 'X' x $len );
  my $sv_contents = peek($sv_ref+0, $svsize);
  my $xpv_contents;

  if (defined $svu_offset) {  # new style 5.10+ SVs
    substr( $sv_contents, $svu_offset, PTR_SIZE ) = _pack_address($location);
  }
  else {  # 5.8 xpv stuff
    my $xpv_addr = unpack(PTR_PACK_TYPE, peek($sv_ref+0, PTR_SIZE) );
    my $xpv_contents = peek( $xpv_addr, $xpv_size ); # we do not care about cur/len

    substr( $xpv_contents, 0, PTR_SIZE ) = _pack_address($location);  # replace pvx in xpv with sanity-checked $location
    substr( $sv_contents, 0, PTR_SIZE) = pack ('P', $xpv_contents );  # replace xpv in sv
  }

  my $new_sv_ref = \ unpack( PTR_PACK_TYPE, pack( 'P', $sv_contents ) );
  my $artificial_string = bless( $new_sv_ref, 'B::PV' )->object_2svref;

  # now when we write to the newly created "string" we are actually writing
  # to $location
  # note we HAVE to use lvalue substr - a plain assignment will add a \0
  substr($$artificial_string, 0, $len) = $bytes;
  return $len;
}

1;
