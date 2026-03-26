use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $simple = run_cli(stdin => '<json>{"x":1}</json>');
is($simple->{exit}, 0, 'extracts JSON from <json> wrapper');
is(decode_json($simple->{stdout})->{x}, 1, 'wrapped JSON parses');

my $other_tag = run_cli(stdin => '<result>{"y":2}</result>');
is($other_tag->{exit}, 0, 'extracts JSON from <result> wrapper');
is(decode_json($other_tag->{stdout})->{y}, 2, 'result wrapper parses');

my $broken = run_cli(stdin => '<json>{"z":3}');
is($broken->{exit}, 0, 'falls back to brace scan when wrapper close tag is missing');
is(decode_json($broken->{stdout})->{z}, 3, 'fallback extraction still valid');

done_testing;
