use strict;
use warnings;
use Test::More;
use File::Spec;
use lib 't/lib';
use TestCLI qw(run_cli fixtures_dir);

my $fixtures_dir = fixtures_dir();
my @input_files;
if (-d $fixtures_dir) {
    opendir(my $dh, $fixtures_dir) or die "opendir $fixtures_dir: $!";
    @input_files = map { File::Spec->catfile($fixtures_dir, $_) }
                   sort grep { /\.in\z/ } readdir($dh);
    closedir $dh;
}
ok(@input_files, 'fixture inputs discovered');

for my $input_file (@input_files) {
    (my $base = $input_file) =~ s/\.in$//;

    open my $in_fh, '<', $input_file or die "open $input_file: $!";
    local $/;
    my $stdin = <$in_fh>;
    close $in_fh;

    my @args;
    if (-f "$base.args") {
        open my $arg_fh, '<', "$base.args" or die "open $base.args: $!";
        while (my $line = <$arg_fh>) {
            chomp $line;
            next unless $line =~ /\S/;
            push @args, split /\s+/, $line;
        }
        close $arg_fh;
    }

    open my $exp_fh, '<', "$base.expected" or die "open $base.expected: $!";
    my $expected = <$exp_fh>;
    {
        local $/;
        $expected .= <$exp_fh> // '';
    }
    close $exp_fh;

    my $want_exit = 0;
    if (-f "$base.exit") {
        open my $exit_fh, '<', "$base.exit" or die "open $base.exit: $!";
        chomp($want_exit = <$exit_fh>);
        $want_exit = int($want_exit);
        close $exit_fh;
    }

    my $res = run_cli(args => \@args, stdin => $stdin);

    is($res->{exit}, $want_exit, "$base exit code");
    is($res->{stdout}, $expected, "$base golden output");
}

done_testing;
