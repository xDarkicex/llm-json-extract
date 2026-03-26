use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $input = join "\n", '{"ok":1}', 'junk', '{"ok":2}', '';
my $res = run_cli(args => ['--jsonl'], stdin => $input);
is($res->{exit}, 0, 'jsonl succeeds when at least one line parses');
my @lines = grep { length } split /\n/, $res->{stdout};
is(scalar @lines, 2, 'jsonl outputs only valid lines');
is(decode_json($lines[0])->{ok}, 1, 'line 1 parsed');
is(decode_json($lines[1])->{ok}, 2, 'line 2 parsed');

my $all_bad = run_cli(args => ['--jsonl'], stdin => "bad\nstill bad\n");
is($all_bad->{exit}, 1, 'jsonl exits 1 when all lines invalid');

my $meta = run_cli(args => ['--jsonl', '--meta'], stdin => $input);
is($meta->{exit}, 0, 'jsonl meta succeeds');
my @meta_lines = grep { length } split /\n/, $meta->{stdout};
is(scalar @meta_lines, 3, 'meta emits success+failure envelopes per non-empty line');
my $e0 = decode_json($meta_lines[0]);
my $e1 = decode_json($meta_lines[1]);
ok($e0->{ok} == 1 && $e1->{ok} == 0, 'jsonl meta contains mixed ok values');

done_testing;
