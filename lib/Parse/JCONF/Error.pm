package Parse::JCONF::Error;

use strict;
use overload '""' => \&to_string;

sub new {
	my ($class, $msg) = @_;
	bless \$msg, $class;
}

sub throw {
	die $_[0];
}

sub to_string {
	my $self = shift;
	return $$self."\n";
}

package Parse::JCONF::Error::IO;
our @ISA = 'Parse::JCONF::Error';

package Parse::JCONF::Error::Parser;
our @ISA = 'Parse::JCONF::Error';

1;
