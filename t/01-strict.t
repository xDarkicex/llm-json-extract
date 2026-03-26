use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $ok = run_cli(args => ['--strict'], stdin => qq|{"a":1,"b":[2,3]}|);
is($ok->{exit}, 0, 'strict mode accepts valid JSON');
my $parsed = decode_json($ok->{stdout});
is($parsed->{a}, 1, 'strict output is valid JSON');

my $bad = run_cli(args => ['--strict'], stdin => "prefix {\"a\":1}");
is($bad->{exit}, 2, 'strict mode fails noisy input');
like($bad->{stderr}, qr/strict/i, 'strict failure is reported');

my $bad_meta = run_cli(args => ['--strict', '--meta'], stdin => "prefix {\"a\":1}");
is($bad_meta->{exit}, 2, 'strict + meta keeps exit code on failure');
my $env = decode_json($bad_meta->{stdout});
is($env->{ok}, 0, 'strict failure meta envelope has ok=0');
is($env->{error}, 'strict_invalid', 'strict failure uses stable error code');

my $bad_fallback = run_cli(args => ['--strict', '--fallback-empty'], stdin => "prefix {\"a\":1}");
is($bad_fallback->{exit}, 2, 'strict + fallback-empty still exits 2');
my $fallback = decode_json($bad_fallback->{stdout});
is_deeply($fallback, {}, 'fallback-empty emits {}');

done_testing;
