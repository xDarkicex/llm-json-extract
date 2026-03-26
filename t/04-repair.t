use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $commented = "{\n  // note\n  \"a\": 1,\n}\n";
my $strict_fail = run_cli(stdin => $commented);
is($strict_fail->{exit}, 1, 'default mode does not parse commented JSON');

my $tolerant = run_cli(args => ['--tolerant'], stdin => $commented);
is($tolerant->{exit}, 0, '--tolerant parses comments and trailing comma');
is(decode_json($tolerant->{stdout})->{a}, 1, 'tolerant output is valid JSON');

my $repair_src = "{foo:'bar', nums:[1,2,],}\n";
my $repair = run_cli(args => ['--repair'], stdin => $repair_src);
is($repair->{exit}, 0, '--repair fixes single quotes and bare keys');
my $obj = decode_json($repair->{stdout});
is($obj->{foo}, 'bar', 'repair fixed key/value quoting');
is_deeply($obj->{nums}, [1,2], 'repair removed trailing comma in array');

done_testing;
