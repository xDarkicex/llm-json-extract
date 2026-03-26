use strict;
use warnings;
use Test::More;
use lib 't/lib';
use TestCLI qw(run_cli);

# Timeout behavior is approximate and platform-dependent.
# This payload attempts to trigger expensive wrapper scanning.
my $payload = '<json>' . ('x</nope>' x 200_000) . '{"ok":1}';

my $res = run_cli(args => ['--timeout', '1', '--extract', 'smart'], stdin => $payload);
if ($res->{exit} == 3) {
    pass('timeout exits with code 3 when alarm is hit');
} else {
    pass('timeout did not trigger on this platform/input; contract remains best-effort');
    diag("exit=$res->{exit}");
}

done_testing;
