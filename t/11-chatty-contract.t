use strict;
use warnings;
use Test::More;
use JSON::PP;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

my $json = JSON::PP->new->canonical(1)->allow_nonref(1);

sub assert_only_requested_json {
    my (%args) = @_;
    my $res = run_cli(args => $args{cli_args} || [], stdin => $args{input});

    is($res->{exit}, 0, $args{name} . ' exits 0')
        or diag($res->{stderr});

    my $decoded = eval { decode_json($res->{stdout}) };
    ok(defined $decoded, $args{name} . ' emits valid JSON only')
        or diag($res->{stdout});

    my $actual = $json->encode($decoded);
    my $want   = $json->encode($args{expected});
    is($actual, $want, $args{name} . ' returns exactly the requested payload');
    is($res->{stdout}, $want . "\n", $args{name} . ' stdout contains JSON only');
}

assert_only_requested_json(
    name     => 'chatty pre/post text',
    input    => "Sure, here is the data you asked for:\n{\"task\":\"extract\",\"ok\":true}\nLet me know if you need edits.",
    expected => { task => 'extract', ok => JSON::PP::true },
);

assert_only_requested_json(
    name     => 'markdown fence with chatter',
    input    => "I analyzed your request.\n```json\n{\"id\":42,\"status\":\"done\"}\n```\nAnything else?",
    expected => { id => 42, status => 'done' },
);

assert_only_requested_json(
    name     => 'first candidate contract with decoy later',
    cli_args => ['--no-largest'],
    input    => "Requested payload:\n{\"request_id\":\"abc123\",\"ok\":true}\nDebug example (ignore): {\"bigger\":{\"nested\":[1,2,3,4]}}",
    expected => { request_id => 'abc123', ok => JSON::PP::true },
);

my $meta = run_cli(
    args  => ['--meta', '--no-largest'],
    stdin => "Answer: {\"kind\":\"meta-check\",\"value\":9}\nOther: {\"kind\":\"noise\",\"value\":10}",
);
is($meta->{exit}, 0, 'meta contract exits 0');
my $env = decode_json($meta->{stdout});
is($env->{ok}, 1, 'meta envelope success');
my $actual_meta = $json->encode($env->{data});
my $want_meta   = $json->encode({ kind => 'meta-check', value => 9 });
is($actual_meta, $want_meta, 'meta envelope data is exactly requested payload');

done_testing;
