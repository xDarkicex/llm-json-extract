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

done_testing;
