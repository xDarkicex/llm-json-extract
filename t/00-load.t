use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli script_path);

ok(-f script_path(), 'script exists');
my $syntax = qx(perl @{[script_path()]} -c 2>&1);
is($? >> 8, 0, 'script compiles cleanly') or diag($syntax);

my $ver = run_cli(args => ['--version']);
is($ver->{exit}, 0, '--version exits 0');
like($ver->{stdout}, qr/v\d+\.\d+\.\d+/, 'version string printed');

done_testing;
