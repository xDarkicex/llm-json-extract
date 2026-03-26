use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $ok = run_cli(args => ['--meta'], stdin => "noise {\"k\":\"v\"} trailing");
is($ok->{exit}, 0, 'meta success exits 0');
my $env = decode_json($ok->{stdout});
is($env->{ok}, 1, 'meta success has ok=1');
is($env->{method}, 'braces', 'meta records extraction method');
is($env->{data}{k}, 'v', 'meta includes parsed data');

my $all = run_cli(args => ['--meta', '--all'], stdin => "{\"a\":1} {\"b\":2}");
is($all->{exit}, 0, '--all + meta exits 0');
my $all_env = decode_json($all->{stdout});
is($all_env->{ok}, 1, '--all + meta ok=1');
is(scalar @{ $all_env->{items} }, 2, '--all + meta includes all parsed objects');

my $fail = run_cli(args => ['--meta'], stdin => "no json here");
is($fail->{exit}, 1, 'meta failure exits 1');
my $fail_env = decode_json($fail->{stdout});
is($fail_env->{ok}, 0, 'meta failure has ok=0');
is($fail_env->{error}, 'not_found', 'meta failure includes stable error code');

done_testing;
