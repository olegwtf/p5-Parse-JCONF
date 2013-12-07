package Parse::JCONF;

use strict;
use Carp;
use Parse::JCONF::Boolean qw(TRUE FALSE);
use Parse::JCONF::Error;

sub new {
	my ($class, %opts) = @_;
	
	my $self = {
		autodie => delete $opts{autodie}
	};
	
	%opts and croak 'unrecognized options: ', join(', ', keys %opts);
	
	bless $self, $class;
}

sub parse {
	my ($self, $data) = @_;
	
	$self->_err(undef);
	
	my %rv;
	my $offset = 0;
	my $line = 1;
	my $len = length $data;
	
	while ($offset < $len && $self->_parse_space_and_comments(\$data, \$offset, \$line)) {
		$self->_parse_bareword(\$data, \$offset, \$line, \my $key)
			or return;
		$self->_parse_eq_sign(\$data, \$offset, \$line)
			or return;
		my $val = $self->_parse_value(\$data, \$offset, \$line, \my $val)
			or return;
		$self->_parse_delim(undef, \$data, \$offset, \$line)
			or return;
		
		$rv{$key} = $val;
	}
	
	return \%rv;
}

sub _parse_space_and_comments {
	my ($self, $data_ref, $offset_ref, $line_ref) = @_;
	
	pos($$data_ref) = $$offset_ref;
	
	while ($$data_ref =~ /\G(?:(\n+)|\s|#[^\n]+)/gc) {
		if (defined $1) {
			$$line_ref += length $1;
		}
	}
	
	$$offset_ref = pos($$data_ref);
	return $$offset_ref < length $$data_ref;
}

sub _parse_bareword {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
		or return $self->_err(
			Parser => "Unexpected end of data, expected bareword at line $$line_ref"
		);
	
	pos($$data_ref) = $$offset_ref;
	
	$$data_ref =~ /\G(\w+)/g
		or return $self->_err(
			Parser => "Expected bareword at line $$line_ref:\n" . _parser_msg($data_ref, $$offset_ref)
		);
	
	$$rv_ref = $1;
	$$offset_ref = pos($$data_ref);
	
	1;
}

sub _parse_delim {
	my ($self, $ok_if, $data_ref, $offset_ref, $line_ref) = @_;
	
	my $line_was = $$line_ref;
	my $has_data = $self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref);
	
	if ($has_data && substr($$data_ref, $$offset_ref, 1) eq ',') {
		# comma delimiter
		$$offset_ref++;
		return 1;
	}
	
	if ($line_was != $$line_ref) {
		# newline delimiter
		return 1;
	}
	
	if (!defined $ok_if && !$has_data) {
		# we may not have delimiter at the end of data
		return 1;
	}
	
	if ($has_data && substr($$data_ref, $$offset_ref, 1) eq $ok_if) {
		# we may not have delimiter at the end of object, array
		return 1;
	}
	
	$self->_err(
		Parser => "Expected delimiter `,' at line $$line_ref:\n" . _parser_msg($data_ref, $$offset_ref)
	);
}

sub _parse_eq_sign {
	my ($self, $data_ref, $offset_ref, $line_ref) = @_;
	
	$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
		or return $self->_err(
			Parser => "Unexpected end of data, expected equals sign `=' at line $$line_ref"
		);
	
	unless (substr($$data_ref, $$offset_ref, 1) eq '=') {
		return $self->_err(
			Parser => "Expected equals sign `=' at line $$line_ref:\n" . _parser_msg($data_ref, $$offset_ref)
		);
	}
	
	$$offset_ref++;
	1;
}

sub _parse_value {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
		or return $self->_err(
			Parser => "Unexpected end of data, expected value at line $$line_ref"
		);
	
	my $c = substr($$data_ref, $$offset_ref, 1);
	if ($c eq '{') {
		$self->_parse_object($data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c eq '[') {
		$self->_parse_array($data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c eq 't') {
		$self->_parse_constant('true', TRUE, $data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c eq 'f') {
		$self->_parse_constant('false', FALSE, $data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c eq 'n') {
		$self->_parse_constant('null', undef, $data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c eq '"') {
		$self->_parse_string($data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	elsif ($c =~ /-|\d/) {
		$self->_parse_number($data_ref, $offset_ref, $line_ref, $rv_ref);
	}
	else {
		$self->_err(
			Parser => "Unexpected value, expected array/object/string/number/true/false/null at line $$line_ref:\n" . 
						_parser_msg($data_ref, $$offset_ref)
		);
	}
}

sub _parse_constant {
	my ($self, $constant, $constant_val, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	my $len = length $constant;
	substr($$data_ref, $$offset_ref, $len) eq $constant && 
	($len + $$offset_ref == length $$data_ref || substr($$data_ref, $$offset_ref+$len, 1) =~ /\s|,/)
		or return $self->_err(
			Parser => "Unexpected value, expected `$constant' at line $$line_ref:\n" .
						_parser_msg($data_ref, $$offset_ref)
		);
	
	$$offset_ref += $len;
	$$rv_ref = $constant_val;
	
	1;
}

sub _parse_number {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	$$data_ref =~ /\G(-?(?:0|[1-9]\d*)(?:\.\d*)?(?:[eE][+-]?\d+)?)/gc
		or return $self->_err(
			Parser => "Unexpected value, expected number at line $$line_ref:\n" .
						_parser_msg($data_ref, $$offset_ref)
		);
	
	my $num = $1;
	$$rv_ref = $num + 0; # WTF: $1 + 0 is string if we can believe Data::Dumper, so use temp var
	$$offset_ref = pos($$data_ref);
	
	1;
}

sub _parse_array {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	$$offset_ref++;
	my @rv;
	
	while (1) {
		$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
			or return $self->_err(
				Parser => "Unexpected end of data, expected end of array `]' at line $$line_ref"
			);
			
		substr($$data_ref, $$offset_ref, 1) eq ']'
			and last;
		$self->_parse_value($data_ref, $offset_ref, $line_ref, \my $val)
			or return;
		$self->_parse_delim(']', $data_ref, $offset_ref, $line_ref)
			or return;
		
		push @rv, $val;
	}
	
	$$rv_ref = \@rv;
	$$offset_ref++;
	
	1;
}

sub _parse_object {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	$$offset_ref++;
	my %rv;
	
	while (1) {
		$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
			or return $self->_err(
				Parser => "Unexpected end of data, expected end of object `}' at line $$line_ref"
			);
		
		substr($$data_ref, $$offset_ref, 1) eq '}'
			and last;
		$self->_parse_bareword($data_ref, $offset_ref, $line_ref, \my $key)
			or return;
		$self->_parse_colon_sign($data_ref, $offset_ref, $line_ref)
			or return;
		$self->_parse_value($data_ref, $offset_ref, $line_ref, \my $val)
			or return;
		$self->_parse_delim('}', $data_ref, $offset_ref, $line_ref)
			or return;
		
		$rv{$key} = $val;
	}
	
	$$rv_ref = \%rv;
	$$offset_ref++;
	
	1;
}

sub _parse_colon_sign {
	my ($self, $data_ref, $offset_ref, $line_ref) = @_;
	
	$self->_parse_space_and_comments($data_ref, $offset_ref, $line_ref)
		or return $self->_err(
			Parser => "Unexpected end of data, expected colon sign `:' at line $$line_ref"
		);
	
	unless (substr($$data_ref, $$offset_ref, 1) eq ':') {
		return $self->_err(
			Parser => "Expected colon sign `:' at line $$line_ref:\n" . _parser_msg($data_ref, $$offset_ref)
		);
	}
	
	$$offset_ref++;
	1;
}

my %ESCAPES = (
	'b'  => "\b",
	'f'  => "\f",
	'n'  => "\n",
	'r'  => "\r",
	't'  => "\t",
	'"'  => '"',
	'\\' => '\\'
);

sub _parse_string {
	my ($self, $data_ref, $offset_ref, $line_ref, $rv_ref) = @_;
	
	pos($$data_ref) = ++$$offset_ref;
	my $str = '';
	
	while ($$data_ref =~ /\G(?:(\n+)|\\((?:[bfnrt"\\]))|\\u([0-9a-fA-F]{4})|([^\\"\x{0}-\x{8}\x{A}-\x{C}\x{E}-\x{1F}]+))/gc) {
		if (defined $1) {
			$$line_ref += length $1;
			$str .= $1;
		}
		elsif (defined $2) {
			$str .= $ESCAPES{$2};
		}
		elsif (defined $3) {
			$str .= pack 'U', hex $3;
		}
		else {
			$str .= $4;
		}
	}
	
	$$offset_ref = pos($$data_ref);
	if ($$offset_ref == length $$data_ref) {
		return $self->_err(
			Parser => "Unexpected end of data, expected string terminator `\"' at line $$line_ref"
		);
	}
	
	if ((my $c = substr($$data_ref, $$offset_ref, 1)) ne '"') {
		if ($c eq '\\') {
			return $self->_err(
				Parser => "Unrecognized escape sequence in string at line $$line_ref:\n" .
							_parser_msg($data_ref, $$offset_ref)
			);
		}
		else {
			my $hex = sprintf('"\x%02x"', ord $c);
			return $self->_err(
				Parser => "Bad character $hex in string at line $$line_ref:\n" .
							_parser_msg($data_ref, $$offset_ref)
			);
		}
	}
	
	$$offset_ref++;
	$$rv_ref = $str;
	
	1;
}

sub parse_file {
	my ($self, $path) = @_;
	
	$self->_err(undef);
	
	open my $fh, '<:utf8', $path
		or return $self->_err(IO => "open `$path': $!");
	
	my $data = do {
		local $/;
		<$fh>;
	};
	
	close $fh;
	
	$self->parse($data);
}

sub last_error {
	return $_[0]->{last_error};
}

sub _err {
	my ($self, $err_type, $msg) = @_;
	
	unless (defined $err_type) {
		$self->{last_error} = undef;
		return;
	}
	
	$self->{last_error} = "Parse::JCONF::Error::$err_type"->new($msg);
	if ($self->{autodie}) {
		$self->{last_error}->throw();
	}
	
	return;
}

sub _parser_msg {
	my ($data_ref, $offset) = @_;
	
	my $msg = '';
	my $non_space_chars = 0;
	my $c;
	my $i;
	
	for ($i=$offset; $i>=0; $i--) {
		$c = substr($$data_ref, $i, 1);
		if ($c eq "\n") {
			last;
		}
		elsif ($c eq "\t") {
			$c = '  ';
		}
		elsif (ord $c < 32) {
			$c = ' ';
		}
		
		substr($msg, 0, 0) = $c;
		
		if ($c =~ /\S/) {
			if (++$non_space_chars > 5) {
				last;
			}
		}
	}
	
	substr($msg, 0, 0) = ' ';
	my $bad_char = length $msg;
	
	my $len = length $$data_ref;
	$non_space_chars = 0;
	
	for ($i=$offset+1; $i<$len; $i++) {
		$c = substr($$data_ref, $i, 1);
		if ($c eq "\n") {
			last;
		}
		elsif ($c eq "\t") {
			$c = '  ';
		}
		elsif (ord $c < 32) {
			$c = ' ';
		}
		
		substr($msg, length $msg) = $c;
		
		if ($c =~ /\S/) {
			if (++$non_space_chars > 3) {
				last;
			}
		}
	}
	
	substr($msg, length $msg) = "\n" . ' 'x($bad_char-1).'^';
	return $msg;
}

1;
