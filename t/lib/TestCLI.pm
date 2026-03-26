package TestCLI;
use strict;
use warnings;
use Exporter 'import';
use IPC::Open3;
use Symbol qw(gensym);
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

our @EXPORT_OK = qw(run_cli decode_json script_path fixtures_dir);

sub repo_root {
    my $base = dirname(__FILE__);
    return abs_path(File::Spec->catdir($base, '..', '..'));
}

sub script_path {
    return File::Spec->catfile(repo_root(), 'llm-json-extract.pl');
}

sub fixtures_dir {
    return File::Spec->catdir(repo_root(), 'tests', 'fixtures');
}

sub run_cli {
    my (%args) = @_;
    my $stdin = defined $args{stdin} ? $args{stdin} : '';
    my @cmd = ('perl', script_path(), @{ $args{args} || [] });

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);
    print {$in} $stdin;
    close $in;

    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    my $exit = $? >> 8;

    return {
        stdout => $stdout,
        stderr => $stderr,
        exit   => $exit,
        cmd    => \@cmd,
    };
}

sub decode_json {
    my ($text) = @_;
    require JSON::PP;
    return JSON::PP->new->allow_nonref(1)->decode($text);
}

1;
