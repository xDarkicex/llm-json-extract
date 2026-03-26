use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $trunc = '{"a":1,"b":[1,2,3]';
my $no_recover = run_cli(args => ['--tolerant'], stdin => $trunc);
is($no_recover->{exit}, 1, 'tolerant alone does not recover truncation');

my $recover = run_cli(args => ['--recover'], stdin => $trunc);
is($recover->{exit}, 0, '--recover restores truncated closing tokens');
my $obj = decode_json($recover->{stdout});
is($obj->{a}, 1, 'recovered JSON parsed correctly');
is_deeply($obj->{b}, [1,2,3], 'recovered array preserved');

my $limited = run_cli(args => ['--recover', '--max-repair-size', '8'], stdin => $trunc);
is($limited->{exit}, 1, 'recovery is skipped when input exceeds max repair size');

done_testing;
