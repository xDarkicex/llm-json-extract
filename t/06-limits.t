use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $too_big = run_cli(args => ['--max-size', '10'], stdin => '{"hello":"world"}');
is($too_big->{exit}, 4, '--max-size enforces hard input cap');

my $cand = run_cli(args => ['--max-candidate', '8'], stdin => 'prefix {"abcdef":123}');
is($cand->{exit}, 1, '--max-candidate skips oversized candidate and returns not found');

my $found_cap = run_cli(args => ['--all', '--max-found', '1'], stdin => '{"a":1} {"b":2}');
is($found_cap->{exit}, 0, '--max-found still returns success');
my @lines = grep { length } split /\n/, $found_cap->{stdout};
is(scalar @lines, 1, '--max-found limits number of emitted objects');

my $attempts = run_cli(args => ['--all', '--max-attempts', '1'], stdin => '{"a":1} {"b":2}');
is($attempts->{exit}, 0, '--max-attempts still allows first accepted candidate');
my @attempt_lines = grep { length } split /\n/, $attempts->{stdout};
is(scalar @attempt_lines, 1, '--max-attempts limits parse attempts');

my $fallback = run_cli(args => ['--max-size', '10', '--fallback-empty'], stdin => '{"hello":"world"}');
is($fallback->{exit}, 4, 'fallback-empty does not mask too-big exit code');
my $empty = decode_json($fallback->{stdout});
is_deeply($empty, {}, 'fallback-empty emits valid JSON on limit failures');

done_testing;
