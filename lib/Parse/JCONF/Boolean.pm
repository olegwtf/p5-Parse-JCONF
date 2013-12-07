package Parse::JCONF::Boolean;

use strict;
use overload '""' => sub { ${$_[0]} }, fallback => 1;

use constant {
	TRUE  => bless(\(my $true  = 1),  __PACKAGE__),
	FALSE => bless(\(my $false = ''), __PACKAGE__)
};

use parent 'Exporter';
our @EXPORT_OK = qw(TRUE FALSE);

1;
