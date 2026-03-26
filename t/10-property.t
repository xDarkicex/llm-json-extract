use strict;
use warnings;
use Test::More;
use JSON::PP;
use lib 't/lib';
use TestCLI qw(run_cli decode_json);

srand 42;
my $json = JSON::PP->new->canonical(1)->allow_nonref(1);

sub rand_word {
    my ($len) = @_;
    my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
    return join '', map { $chars[int rand @chars] } 1..$len;
}

sub noisy_wrap {
    my ($payload) = @_;
    my @prefix = ('', 'Answer: ', "```json\n", '<json>', '/*note*/ ');
    my @suffix = ('', ' thanks', "\n```", '</json>', ' //done');
    return $prefix[int rand @prefix] . $payload . $suffix[int rand @suffix];
}

for my $i (1..80) {
    my $obj = {
        id    => $i,
        token => rand_word(6),
        nums  => [ map { int rand 100 } 1..(1 + int rand 4) ],
    };
    my $payload = $json->encode($obj);

    my $strict = run_cli(args => ['--strict'], stdin => $payload);
    is($strict->{exit}, 0, "strict accepts canonical JSON (iter $i)");
    my $strict_obj = decode_json($strict->{stdout});
    is($strict_obj->{id}, $i, "strict output preserved id (iter $i)");

    my $wrapped = noisy_wrap($payload);
    my $meta = run_cli(args => ['--meta', '--recover', '--fallback-empty'], stdin => $wrapped);

    my $env = eval { decode_json($meta->{stdout}) };
    ok(defined $env, "meta output always valid JSON (iter $i)")
        or diag($meta->{stdout});

    ok(exists $env->{ok}, "meta envelope has ok field (iter $i)");
    ok(exists $env->{version}, "meta envelope has version field (iter $i)");

    if ($env->{ok}) {
        my $inner = eval { $json->encode($env->{data}) };
        ok(defined $inner, "successful meta includes encodable data (iter $i)");
    }

    my $fallback = run_cli(args => ['--strict', '--fallback-empty'], stdin => $wrapped);
    my $fobj = eval { decode_json($fallback->{stdout}) };
    ok(defined $fobj, "fallback-empty never emits malformed JSON (iter $i)");
}

for my $i (1..120) {
    my $target = {
        req_id => "req_$i",
        ok     => JSON::PP::true,
        value  => int(rand(10_000)),
    };
    my $target_json = $json->encode($target);

    my $decoy = {
        noise => rand_word(5),
        nums  => [ map { int rand 100 } 1..(3 + int rand 5) ],
        deep  => { a => 1, b => [2, 3, 4] },
    };
    my $decoy_json = $json->encode($decoy);

    my @prefix = (
        "Sure, here is the requested payload:\n",
        "I will return JSON only.\n",
        "<answer>\n",
        "```text\nanalysis omitted\n```\n",
    );
    my @joiner = (
        "\nThanks!",
        "\nAdditional commentary follows.",
        "\n<notes>not json</notes>",
        "\nFinal answer above.",
    );
    my @decoy_tail = (
        '',
        "\nIgnore this demo object: $decoy_json",
        "\nExample template (not requested): $decoy_json",
    );

    my $input = $prefix[int rand @prefix]
        . $target_json
        . $joiner[int rand @joiner]
        . $decoy_tail[int rand @decoy_tail];

    my $res = run_cli(args => ['--no-largest'], stdin => $input);
    is($res->{exit}, 0, "chatty contract exits 0 (iter $i)");
    my $decoded = eval { decode_json($res->{stdout}) };
    ok(defined $decoded, "chatty contract emits valid JSON only (iter $i)")
        or diag($res->{stdout});

    my $actual = defined $decoded ? $json->encode($decoded) : '';
    is($actual, $target_json, "chatty contract returns requested payload exactly (iter $i)");
    is($res->{stdout}, $target_json . "\n", "chatty contract stdout has no extra text (iter $i)");

    my $meta = run_cli(args => ['--meta', '--no-largest'], stdin => $input);
    is($meta->{exit}, 0, "chatty meta exits 0 (iter $i)");
    my $env = eval { decode_json($meta->{stdout}) };
    ok(defined $env && $env->{ok}, "chatty meta envelope is valid success (iter $i)");
    my $meta_actual = (defined $env && $env->{ok}) ? $json->encode($env->{data}) : '';
    is($meta_actual, $target_json, "chatty meta data matches requested payload (iter $i)");
}

done_testing;
