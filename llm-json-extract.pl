#!/usr/bin/env perl

# ==============================================================================
# llm-json-extract.pl - High-Assurance JSON Extraction & Recovery for LLM Output
# ==============================================================================
# GitHub:  https://github.com/xDarkicex/llm-json-extract
# License: MIT © 2026 xDarkicex
# Purpose: Extract, validate, repair, and recover well-formed JSON from noisy,
#          chatty, truncated, or wrapper-heavy LLM responses for reliable use in
#          production pipelines, APIs, and frontend applications.
# ==============================================================================

use strict;
use warnings;
use utf8;
use Config;
use Encode qw(decode FB_DEFAULT FB_CROAK);
use Getopt::Long qw(:config no_ignore_case bundling);

# ---------------------------------------------------------------------------
# Exit codes
# ---------------------------------------------------------------------------
use constant {
    EXIT_OK       => 0,   # JSON found and printed
    EXIT_NOTFOUND => 1,   # No valid JSON found
    EXIT_INVALID  => 2,   # Bad input / --strict failure / bad options
    EXIT_TIMEOUT  => 3,   # --timeout exceeded
    EXIT_TOOBIG   => 4,   # Input exceeds --max-size
};
use constant VERSION => '3.9.0';

# ---------------------------------------------------------------------------
# Optional modules
# ---------------------------------------------------------------------------
my $HAS_HIRESTIME = eval { require Time::HiRes; 1 };
my $HAS_ALARM     = $Config{d_alarm};
my $t0            = $HAS_HIRESTIME ? Time::HiRes::time() : time();

BEGIN {
    eval { require JSON::MaybeXS }
      or eval { require JSON::PP }
      or die "json-extract.pl: no JSON module (install JSON::PP or JSON::MaybeXS)\n";
}

binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
my %opt = (
    pretty            => 0,
    all               => 0,
    strict            => 0,
    jsonl             => 0,
    verbose           => 0,
    stats             => 0,
    extract           => 'smart',   # smart | fences | braces
    'max-size'        => 0,         # 0 = unlimited
    'max-depth'       => 512,
    sanitize          => 0,
    tolerant          => 0,
    repair            => 0,         # superset of tolerant: also fixes keys/single-quotes
    recover           => 0,         # try to close truncated JSON by appending missing } / ]
    largest           => 1,         # ON by default: pick largest valid JSON, not leftmost
    timeout           => 0,         # seconds, 0 = off
    'max-attempts'    => 0,         # 0 = unlimited parse attempts
    'max-candidate'   => 0,         # 0 = unlimited candidate size (bytes)
    'max-repair-size' => '5M',      # limit expensive tolerant/repair/recovery work
    'max-found'       => 0,         # 0 = unlimited accepted candidates
    'fallback-empty'  => 0,         # output {} on failure instead of nothing
    'log-json'        => 0,         # structured JSON lines on STDERR
    meta              => 0,         # emit metadata envelope to STDOUT
    version           => 0,
    help              => 0,
);

GetOptions(
    'pretty'            => \$opt{pretty},
    'all'               => \$opt{all},
    'strict'            => \$opt{strict},
    'jsonl'             => \$opt{jsonl},
    'verbose|v'         => \$opt{verbose},
    'stats'             => \$opt{stats},
    'extract=s'         => \$opt{extract},
    'max-size=s'        => \$opt{'max-size'},
    'max-depth=i'       => \$opt{'max-depth'},
    'sanitize'          => \$opt{sanitize},
    'tolerant'          => \$opt{tolerant},
    'repair'            => \$opt{repair},
    'recover'           => \$opt{recover},
    'largest!'          => \$opt{largest},      # --largest / --no-largest
    'timeout=i'         => \$opt{timeout},
    'max-attempts=i'    => \$opt{'max-attempts'},
    'max-candidate=s'   => \$opt{'max-candidate'},
    'max-repair-size=s' => \$opt{'max-repair-size'},
    'max-found=i'       => \$opt{'max-found'},
    'fallback-empty'    => \$opt{'fallback-empty'},
    'log-json'          => \$opt{'log-json'},
    'meta'              => \$opt{meta},
    'version'           => \$opt{version},
    'help|h'            => \$opt{help},
) or usage(EXIT_INVALID);

if ($opt{version}) {
    print STDOUT "json-extract.pl v", VERSION, "\n";
    exit EXIT_OK;
}

usage(EXIT_OK) if $opt{help};

$opt{tolerant} = 1 if $opt{repair} || $opt{recover};   # --repair/--recover imply --tolerant

unless ($opt{extract} =~ /\A (smart|fences|braces) \z/x) {
    die "json-extract.pl: --extract must be 'smart', 'fences', or 'braces'\n";
}

my $MAX_BYTES        = parse_size($opt{'max-size'});
my $MAX_CAND         = parse_size($opt{'max-candidate'});
my $MAX_REPAIR_INPUT = parse_size($opt{'max-repair-size'});
my $MAX_ATTEMPTS     = $opt{'max-attempts'};
my $MAX_FOUND        = $opt{'max-found'};
# Expensive tolerant/repair/recovery work is capped by the smaller of
# --max-candidate and --max-repair-size when both are set; otherwise use
# whichever limit is present.
my $MAX_REPAIR_SIZE  = $MAX_CAND && $MAX_REPAIR_INPUT
    ? ($MAX_CAND < $MAX_REPAIR_INPUT ? $MAX_CAND : $MAX_REPAIR_INPUT)
    : ($MAX_CAND || $MAX_REPAIR_INPUT || 5 * 1024 * 1024);

# ---------------------------------------------------------------------------
# Codec singletons — class name, not instance (avoids "bless into a ref" bug)
# ---------------------------------------------------------------------------
my $JSON_CLASS = eval { require JSON::MaybeXS; 'JSON::MaybeXS' } // 'JSON::PP';
my ($DECODER, $RELAXED_DECODER, $ENCODER);
my $HAS_RELAXED = 0;

sub _init_codecs {
    $DECODER = $JSON_CLASS->new->allow_nonref(1)->max_depth($opt{'max-depth'});
    $ENCODER = $JSON_CLASS->new->canonical(1)->allow_nonref(1);
    $ENCODER->pretty(1)->indent(2) if $opt{pretty};

    # Relaxed decoder: handles trailing commas natively (CPanel::JSON::XS / JSON::PP >=4)
    if ($opt{tolerant}) {
        my $rd = $JSON_CLASS->new->allow_nonref(1)->max_depth($opt{'max-depth'});
        if (eval { $rd->relaxed(1); 1 }) {
            $RELAXED_DECODER = $rd;
            $HAS_RELAXED     = 1;
        }
    }
}
_init_codecs();

# ---------------------------------------------------------------------------
# Top-level crash containment — nothing leaks to the caller unhandled
# ---------------------------------------------------------------------------
my $exit_code = eval { run_main() };
if ($@) {
    my $err = $@;
    $err =~ s/[\r\n]+/ /g;
    $err = substr($err, 0, 300);
    warn "json-extract.pl: INTERNAL_ERROR: $err\n";
    print "{}\n" if $opt{'fallback-empty'};
    exit EXIT_INVALID;
}
exit($exit_code // EXIT_INVALID);

# ===========================================================================
# run_main() -> exit code
# ===========================================================================
sub preview_text {
    my ($s, $limit) = @_;
    $limit ||= 120;
    return '' unless defined $s && length $s;
    $s =~ s/[\r\n\t]+/ /g;
    $s =~ s/\s{2,}/ /g;
    return length($s) > $limit ? substr($s, 0, $limit) . '...' : $s;
}

sub emit_failure_output {
    my ($code, $error, $preview) = @_;

    if ($opt{meta}) {
        my $payload = {
            ok      => 0,
            version => VERSION,
            error   => $error,
            exit    => $code,
        };
        $payload->{preview} = preview_text($preview) if defined $preview && length $preview;
        emit_validated($payload);
    } elsif ($opt{'fallback-empty'}) {
        print "{}\n";
    }
}

sub emit_success_output {
    my ($method, $found_ref) = @_;
    my @found = @$found_ref;

    if ($opt{all}) {
        if ($opt{meta}) {
            emit_validated({
                ok      => 1,
                version => VERSION,
                method  => $method // 'unknown',
                found   => scalar @found,
                items   => [ map { $_->{data} } @found ],
            });
        } else {
            for my $item (@found) {
                print $ENCODER->encode($item->{data}), "\n";
            }
        }
        return;
    }

    my $chosen = $opt{largest}
        ? (sort { $b->{len} <=> $a->{len} } @found)[0]
        : $found[0];

    if ($opt{meta}) {
        emit_validated({
            ok           => 1,
            version      => VERSION,
            method       => $method // 'unknown',
            found        => scalar @found,
            selected_len => $chosen->{len},
            data         => $chosen->{data},
        });
    } else {
        emit_validated($chosen->{data});
    }
}

sub parse_one_with_timeout {
    my ($text) = @_;
    return with_timeout($opt{timeout}, sub {
        my $parsed = try_parse_with_fallback($text);
        return { ok => defined($parsed) ? 1 : 0, data => $parsed };
    });
}

sub run_strict_mode {
    my ($input, $orig_len) = @_;
    (my $trimmed = $input) =~ s/\A\s+|\s+\z//g;

    my $strict_result = parse_one_with_timeout($trimmed);
    unless (defined $strict_result) {
        emit_failure_output(EXIT_TIMEOUT, 'timeout', $trimmed);
        return EXIT_TIMEOUT;
    }

    if ($strict_result->{ok}) {
        emit_validated($strict_result->{data});
        print_stats($orig_len, 'strict', 1);
        return EXIT_OK;
    }

    warn "json-extract.pl: input is not valid JSON (--strict)\n";
    emit_failure_output(EXIT_INVALID, 'strict_invalid', $trimmed);
    return EXIT_INVALID;
}

sub run_jsonl_mode {
    my ($input, $orig_len) = @_;

    my $result = with_timeout($opt{timeout}, sub {
        my @lines_out;
        my $count = 0;

        for my $line (split /\n/, $input) {
            $line =~ s/\A\s+|\s+\z//g;
            next unless length $line;

            my $data = try_parse_with_fallback($line);
            if (defined $data) {
                push @lines_out, $opt{meta}
                    ? $ENCODER->encode({
                        ok      => 1,
                        version => VERSION,
                        method  => 'jsonl',
                        data    => $data,
                    })
                    : $ENCODER->encode($data);
                $count++;
            } else {
                my $preview = substr($line, 0, 60);
                $preview =~ s/[\r\n]+/ /g;
                log_v("JSONL: skipping invalid line: $preview");

                if ($opt{meta}) {
                    push @lines_out, $ENCODER->encode({
                        ok      => 0,
                        version => VERSION,
                        method  => 'jsonl',
                        error   => 'invalid_line',
                        preview => preview_text($line),
                    });
                }
            }
        }

        return { count => $count, lines => \@lines_out };
    });

    unless (defined $result) {
        emit_failure_output(EXIT_TIMEOUT, 'timeout', $input);
        return EXIT_TIMEOUT;
    }

    print $_, "\n" for @{ $result->{lines} };

    unless ($result->{count}) {
        warn "json-extract.pl: no valid JSON lines found\n";
        emit_failure_output(EXIT_NOTFOUND, 'jsonl_not_found', $input);
        return EXIT_NOTFOUND;
    }

    print_stats($orig_len, 'jsonl', $result->{count});
    return EXIT_OK;
}

sub run_main {

    # --- Read input as raw bytes, decode UTF-8 ourselves --------------------
    log_v("Reading input...");

    my $raw;
    if (@ARGV) {
        my $file = $ARGV[0];
        open my $fh, '<:raw', $file
            or die "json-extract.pl: cannot open '$file': $!\n";
        local $/; $raw = <$fh>; close $fh;
    } else {
        binmode STDIN, ':raw';
        local $/; $raw = <STDIN>;
    }

    unless (defined $raw && length $raw) {
        warn "json-extract.pl: empty input\n";
        emit_failure_output(EXIT_NOTFOUND, 'empty');
        print_stats(0, 'empty', 0);
        return EXIT_NOTFOUND;
    }

    # Size check on raw bytes before any processing
    if ($MAX_BYTES && length($raw) > $MAX_BYTES) {
        warn sprintf "json-extract.pl: input (%d bytes) exceeds --max-size\n", length $raw;
        emit_failure_output(EXIT_TOOBIG, 'too_big');
        return EXIT_TOOBIG;
    }

    # UTF-8 decode: replace bad sequences with U+FFFD rather than dying.
    # Some LLM outputs have truncated multi-byte chars at chunk boundaries.
    my $input = eval { decode('UTF-8', $raw, FB_CROAK) };
    if ($@) {
        log_v("WARNING: invalid UTF-8 detected; replacing bad sequences with U+FFFD");
        $input = decode('UTF-8', $raw, FB_DEFAULT);
    }
    $raw = undef;   # release raw bytes early

    log_v(sprintf "Input: %d chars", length $input);
    $input =~ s/\A\x{FEFF}//;   # strip UTF-8 BOM if present
    $input =~ s/\r\n/\n/g;

    # Binary content guard (>=20 consecutive control chars is almost certainly binary)
    if ($input =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]{20,}/) {
        warn "json-extract.pl: input appears to be binary; use --sanitize to strip controls\n";
        unless ($opt{sanitize}) {
            emit_failure_output(EXIT_INVALID, 'binary_input', $input);
            return EXIT_INVALID;
        }
    }

    # Sanitize: strip null bytes and stray ASCII control chars
    if ($opt{sanitize}) {
        my $before  = length $input;
        $input      =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;
        my $removed = $before - length $input;
        log_v("Sanitized $removed control character(s)") if $removed;
    }

    my $entity_decoded_input = $input;
    if (has_basic_html_entities($input)) {
        $entity_decoded_input = decode_basic_html_entities($input);
        if (defined $entity_decoded_input && $entity_decoded_input ne $input) {
            log_v("Decoded common HTML entities before parsing");
        }
    }

    # --- --strict: entire input must be JSON --------------------------------
    if ($opt{strict}) {
        my $strict_input = $opt{tolerant} ? $entity_decoded_input : $input;
        return run_strict_mode($strict_input, length $input);
    }

    # --- --jsonl: one JSON object per line ----------------------------------
    if ($opt{jsonl}) {
        my $jsonl_input = $opt{tolerant} ? $entity_decoded_input : $input;
        return run_jsonl_mode($jsonl_input, length $input);
    }

    # --- Normal extraction (with optional timeout) --------------------------
    my $extract_input = $entity_decoded_input;
    my $result = with_timeout($opt{timeout}, sub { extract_all($extract_input) });

    unless (defined $result) {
        emit_failure_output(EXIT_TIMEOUT, 'timeout', $extract_input);
        return EXIT_TIMEOUT;
    }

    my ($method, @found) = @$result;

    unless (@found) {
        warn "json-extract.pl: No valid JSON found\n";
        emit_failure_output(EXIT_NOTFOUND, 'not_found', $extract_input);
        print_stats(length $input, 'none', 0);
        return EXIT_NOTFOUND;
    }

    emit_success_output($method, \@found);

    print_stats(length $input, $method // 'unknown', scalar @found);
    return EXIT_OK;
}

# ===========================================================================
# Extraction helpers
# ===========================================================================
sub has_basic_html_entities {
    my ($s) = @_;
    return 0 unless defined $s && length $s;
    return $s =~ /&(quot|apos|amp|lt|gt|#\d+|#x[0-9A-Fa-f]+);/i ? 1 : 0;
}

sub decode_basic_html_entities {
    my ($s) = @_;
    return undef unless defined $s && length $s;

    $s =~ s/&#(x?[0-9A-Fa-f]+);/_decode_html_numeric($1)/ge;
    $s =~ s/&quot;/"/gi;
    $s =~ s/&apos;/'/gi;
    $s =~ s/&amp;/&/gi;
    $s =~ s/&lt;/</gi;
    $s =~ s/&gt;/>/gi;

    return $s;
}

sub _decode_html_numeric {
    my ($raw) = @_;
    my $code = ($raw =~ /^x/i) ? hex(substr($raw, 1)) : int($raw);
    return '' if $code < 0 || $code > 0x10FFFF;
    return chr($code);
}

# Wrapper extraction deliberately avoids a single regex with a large payload capture.
# Scanning for '</' plus a short anchored tag check is easier to bound and reason about
# under adversarial input than a broad non-greedy capture.
sub extract_wrapper_candidates {
    my ($text) = @_;
    my @out;

    my $iterations = 0;
    my $warned_iterations = 0;
    pos($text) = 0;
    while ($text =~ m{<(json|output|result|answer|data)\b[^>]*>}gi) {
        my $tag = lc $1;
        my $content_start = pos($text);
        my $scan = $content_start;

        while (1) {
            $iterations++;
            if (!$warned_iterations && $iterations > 10_000) {
                log_v("WARNING: wrapper-tag scan exceeded 10000 inner iterations");
                $warned_iterations = 1;
            }
            my $close_pos = index($text, '</', $scan);
            last if $close_pos < 0;

            my $probe = substr($text, $close_pos, length($tag) + 8);
            if ($probe =~ m{\A</\Q$tag\E\s*>}i) {
                push @out, substr($text, $content_start, $close_pos - $content_start);
                last;
            }

            $scan = $close_pos + 2;
        }
    }

    return @out;
}

sub strip_jsonish_comments {
    my ($str) = @_;
    return $str unless defined $str && length $str;

    my $len    = length $str;
    my $i      = 0;
    my $in_str = 0;
    my $out    = '';

    while ($i < $len) {
        my $ch = substr($str, $i, 1);

        if ($in_str) {
            if ($ch eq '\\' && $i + 1 < $len) {
                $out .= substr($str, $i, 2);
                $i += 2;
                next;
            }
            $out .= $ch;
            $in_str = 0 if $ch eq '"';
            $i++;
            next;
        }

        if ($ch eq '"') {
            $out .= $ch;
            $in_str = 1;
            $i++;
            next;
        }

        if ($ch eq '/' && $i + 1 < $len) {
            my $next = substr($str, $i + 1, 1);

            if ($next eq '/') {
                $i += 2;
                $i++ while $i < $len && substr($str, $i, 1) ne "\n";
                next;
            }

            if ($next eq '*') {
                my $end = index($str, '*/', $i + 2);
                if ($end < 0) {
                    log_v(sprintf "WARNING: unclosed /* comment at offset %d; truncating output", $i);
                    last;
                }
                $i = $end + 2;
                next;
            }
        }

        if ($ch eq '#') {
            $i++;
            $i++ while $i < $len && substr($str, $i, 1) ne "\n";
            next;
        }

        $out .= $ch;
        $i++;
    }

    return $out;
}

sub recover_truncated {
    my ($str) = @_;
    return undef unless defined $str && length $str;

    my @stack;
    my $in_str = 0;
    my $len    = length $str;
    my $i      = 0;

    while ($i < $len) {
        my $ch = substr($str, $i, 1);

        if ($in_str) {
            if ($ch eq '\\' && $i + 1 < $len) { $i += 2; next }
            if ($ch eq '"') { $in_str = 0 }
            $i++;
            next;
        }

        if    ($ch eq '"')               { $in_str = 1 }
        elsif ($ch eq '{' || $ch eq '[') { push @stack, $ch }
        elsif ($ch eq '}' || $ch eq ']') {
            return undef unless @stack;
            my $want = pop @stack;
            return undef if ($want eq '{' && $ch ne '}') || ($want eq '[' && $ch ne ']');
        }
        $i++;
    }

    return undef if $in_str || !@stack;
    return undef if @stack >= $opt{'max-depth'};

    my $recovered = $str;
    $recovered =~ s/[\s,]+\z//;
    $recovered .= join '', reverse map { $_ eq '{' ? '}' : ']' } @stack;

    return undef if $recovered eq $str;
    return { text => $recovered, appended => scalar @stack };
}

# ===========================================================================
# extract_all($text) -> [$method, {data=>..., len=>...}, ...]
# ===========================================================================
sub process_candidate {
    my ($candidate, $label, $method_name, $found_ref, $method_ref, $attempts_ref, $count_attempt) = @_;

    $candidate =~ s/\A\s+|\s+\z//g if defined $candidate;
    return { accepted => 0, stop => 0 } unless defined $candidate && length $candidate;

    if ($count_attempt) {
        $$attempts_ref++;
        return { accepted => 0, stop => 1 } if $MAX_ATTEMPTS && $$attempts_ref > $MAX_ATTEMPTS;
    }

    my $clen = length $candidate;
    return { accepted => 0, stop => 0 } if $MAX_CAND && $clen > $MAX_CAND;

    log_v(sprintf "  Candidate (%s): %d chars", $label, $clen);

    my $data = try_parse_with_fallback($candidate);
    return { accepted => 0, stop => 0 } unless defined $data;

    push @$found_ref, { data => $data, len => $clen };
    $$method_ref //= $method_name;
    log_v("  => Accepted ($method_name)");

    my $stop = ($MAX_FOUND && @$found_ref >= $MAX_FOUND) || !($opt{all} || $opt{largest});
    return { accepted => 1, stop => $stop };
}

sub extract_all {
    my ($text) = @_;
    my @found;
    my $method;
    my $attempts = 0;

    # ----- Strategy 0: XML/HTML wrapper tags --------------------------------
    if ($opt{extract} eq 'smart') {
        log_v("Trying wrapper-tag extraction...");
        for my $candidate (extract_wrapper_candidates($text)) {
            my $res = process_candidate($candidate, 'tags', 'tags', \@found, \$method, \$attempts, 1);
            return [$method, @found] if $res->{stop};
        }
    }

    # ----- Strategy 1: Code fences ------------------------------------------
    if ($opt{extract} ne 'braces') {
        log_v("Trying code-fence extraction...");

        my @fence_specs = (
            { name => 'backticks', pat => qr/```(?:json[ \t]*)?\r?\n?((?:(?!```)[\s\S])*?)```/ },
            { name => 'tildes',    pat => qr/~~~(?:json[ \t]*)?\r?\n?((?:(?!~~~)[\s\S])*?)~~~/ },
        );

        for my $spec (@fence_specs) {
            pos($text) = 0;
            while ($text =~ /$spec->{pat}/gi) {
                my $label = "fence:$spec->{name}";
                my $res = process_candidate($1, $label, 'fences', \@found, \$method, \$attempts, 1);
                return [$method, @found] if $res->{stop};
            }
            last if $MAX_ATTEMPTS && $attempts > $MAX_ATTEMPTS;
        }
    }

    # ----- Strategy 2: Sequential brace/bracket scanning -------------------
    if ($opt{extract} ne 'fences') {
        log_v("Trying brace/bracket scanning...");

        my $tlen            = length $text;
        my $pos             = 0;
        my $last_accept_end = -1;

        while ($pos < $tlen) {
            last if $MAX_ATTEMPTS && $attempts > $MAX_ATTEMPTS;

            my $ch = substr($text, $pos, 1);

            if ($ch eq '{' || $ch eq '[') {
                if ($pos < $last_accept_end) {
                    $pos++;
                    next;
                }

                my $candidate = extract_from($text, $pos, $ch);
                if (defined $candidate) {
                    my $end = $pos + length($candidate);
                    my $res = process_candidate($candidate, "braces:$pos-$end", 'braces', \@found, \$method, \$attempts, 1);
                    if ($res->{accepted}) {
                        $last_accept_end = $end;
                        return [$method, @found] if $res->{stop};
                        $pos = $end;
                        next;
                    }
                    last if $MAX_ATTEMPTS && $attempts > $MAX_ATTEMPTS;
                }
            }
            $pos++;
        }
    }

    # ----- Strategy 3: Full-input fallback (smart / braces only) -----------
    if (!@found && $opt{extract} ne 'fences') {
        log_v("Trying full-input fallback...");
        my $res = process_candidate($text, 'fallback', 'fallback', \@found, \$method, \$attempts, 0);
        return [$method, @found] if $res->{stop};
    }

    return [$method, @found];
}

# ===========================================================================
# State-machine brace extractor
#
# Input is a decoded Perl character string (via Encode::decode above).
# In character-string context substr($text,$i,1) returns one Unicode codepoint.
# JSON structural chars ({, }, [, ], ", \) are all US-ASCII (U+007B etc.) and
# can never appear as continuation bytes of a UTF-8 sequence, so this is safe.
# ===========================================================================
sub extract_from {
    my ($text, $start, $opener) = @_;
    my $closer = ($opener eq '{') ? '}' : ']';
    my $len    = length $text;
    my $depth  = 0;
    my $in_str = 0;
    my $i      = $start;

    while ($i < $len) {
        my $ch = substr($text, $i, 1);

        if ($in_str) {
            if ($ch eq '\\' && $i + 1 < $len) { $i += 2; next }   # skip escape pair
            $in_str = 0 if $ch eq '"';
            $i++; next;
        }

        if    ($ch eq '"')               { $in_str = 1 }
        elsif ($ch eq '{' || $ch eq '[') { $depth++ }
        elsif ($ch eq '}' || $ch eq ']') {
            if (--$depth == 0) {
                return $ch eq $closer
                    ? substr($text, $start, $i - $start + 1)
                    : undef;   # mismatched bracket type
            }
        }
        $i++;
    }
    return undef;   # unmatched opener
}

# ===========================================================================
# Parsing
# ===========================================================================
sub can_attempt_expensive_fallback {
    my ($str) = @_;
    return 0 unless defined $str && length $str;
    return 1 unless $opt{tolerant};
    return length($str) <= $MAX_REPAIR_SIZE ? 1 : 0;
}

sub try_parse {
    my ($str) = @_;
    return undef unless defined $str && length $str;
    my $data = eval { $DECODER->decode($str) };
    return undef if $@ || !defined $data || !ref $data;
    return $data;
}

sub try_parse_with_fallback {
    my ($str) = @_;

    my $data = try_parse($str);
    return $data if defined $data;

    return undef unless $opt{tolerant};

    # 1. Relaxed decoder handles trailing commas / relaxed whitespace natively
    #    (Cpanel::JSON::XS and recent JSON::PP support ->relaxed)
    if ($HAS_RELAXED && defined $RELAXED_DECODER) {
        $data = eval { $RELAXED_DECODER->decode($str) };
        return $data if !$@ && defined $data && ref $data;
    }

    my $cleaned;
    if (can_attempt_expensive_fallback($str)) {
        # 2. Pre-processor: normalise common LLM output quirks then re-parse
        $cleaned = tolerate($str);
        if (defined $cleaned && $cleaned ne $str) {
            log_v("    Trying pre-processed candidate...");
            $data = try_parse($cleaned);
            return $data if defined $data;

            # Also try relaxed decoder on the cleaned string
            if ($HAS_RELAXED && defined $RELAXED_DECODER) {
                $data = eval { $RELAXED_DECODER->decode($cleaned) };
                return $data if !$@ && defined $data && ref $data;
            }
        }
    } elsif ($opt{repair} || $opt{recover} || $opt{tolerant}) {
        log_v(sprintf "    Skipping tolerant preprocessing for candidate over %d bytes", $MAX_REPAIR_SIZE);
    }

    # 3. Recover truncated JSON by appending the minimal closing sequence
    if ($opt{recover}) {
        my @recovery_inputs = grep { defined && length } ($cleaned, $str);
        my %seen;

        for my $candidate (@recovery_inputs) {
            next if $seen{$candidate}++;
            next unless can_attempt_expensive_fallback($candidate);

            my $recovered = recover_truncated($candidate);
            next unless $recovered && ref $recovered eq 'HASH';

            log_v(sprintf "    Trying recovered candidate (%d closing token(s) appended)...",
                $recovered->{appended});

            $data = try_parse($recovered->{text});
            return $data if defined $data;

            if ($HAS_RELAXED && defined $RELAXED_DECODER) {
                $data = eval { $RELAXED_DECODER->decode($recovered->{text}) };
                return $data if !$@ && defined $data && ref $data;
            }
        }
    }

    return undef;
}

sub _single_quoted_to_json_string {
    my ($c) = @_;
    $c =~ s/\\/\\\\/g;
    $c =~ s/"/\\"/g;
    return '"' . $c . '"';
}

# ---------------------------------------------------------------------------
# tolerate($str) — pre-processor for near-valid JSON
#
# Level 1 (--tolerant): smart/curly quotes, comments (//, #, /* */), trailing commas
# Level 2 (--repair):   + single-quoted strings, unquoted object keys
#
# CAUTION (--repair): key-quoting regex is best-effort and may incorrectly
# alter identifiers that appear inside string values. Always verify output.
# ---------------------------------------------------------------------------
sub tolerate {
    my ($str) = @_;
    return undef unless defined $str && length $str;

    # 1. Normalise curly/smart quotes to plain ASCII equivalents
    $str =~ s/[\x{201C}\x{201D}]/"/g;   # " "  =>  "
    $str =~ s/[\x{2018}\x{2019}]/'/g;   # ' '  =>  '

    # 2. Strip comments outside strings with a state machine to avoid regex backtracking.
    $str = strip_jsonish_comments($str);

    if ($opt{repair}) {
        # 3. Single-quoted strings => double-quoted.
        $str =~ s{'((?:[^'\\\\]|\\\\.)*)'}{ _single_quoted_to_json_string($1) }ge;

        # 4. Unquoted object keys => quoted.
        #    Matches bare identifiers after { or , with optional whitespace.
        #    Best-effort: may misfire on identifiers inside string values.
        $str =~ s/([,{]\s*)([a-zA-Z_\$][a-zA-Z0-9_\$]*)(\s*:)/$1.q(").$2.q(").$3/ge;
    }

    # 5. Remove trailing commas before ] or } (common LLM mistake).
    #    Iteration guard prevents an infinite loop on pathological input.
    my $tc_iter = 0;
    while ($str =~ s/,\s*([}\]])/$1/g) {
        last if ++$tc_iter >= 1_000;
    }
    log_v("WARNING: tolerate() trailing-comma loop hit iteration limit")
        if $tc_iter >= 1_000;

    $str =~ s/\A\s+|\s+\z//g;
    return $str;
}

# ===========================================================================
# Output
# ===========================================================================

# Encode and round-trip validate before printing. If the encode->decode cycle
# fails something is deeply wrong; die (caught by top-level eval) rather than
# emit invalid JSON to the frontend.
sub emit_validated {
    my ($data) = @_;

    my $out = eval { $ENCODER->encode($data) };
    die "json-extract.pl: encode failed: $@\n" if $@ || !defined $out;

    eval { $DECODER->decode($out) };
    die "json-extract.pl: round-trip validation failed: $@\n" if $@;

    $out =~ s/\n\z// unless $opt{pretty};
    print $out, "\n";
}

# ===========================================================================
# Utilities
# ===========================================================================

# Run $code with an optional SIGALRM timeout.
# Returns arrayref/hashref/scalar from $code, or undef on timeout.
sub with_timeout {
    my ($seconds, $code) = @_;

    unless ($HAS_ALARM && $seconds > 0) {
        return $code->();
    }

    my $result;
    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };
        alarm($seconds);
        $result = $code->();
        alarm(0);
    };
    alarm(0);   # always cancel, even on exception

    if (defined $@ && $@ eq "TIMEOUT\n") {
        warn "json-extract.pl: extraction timed out after ${seconds}s\n";
        return undef;
    } elsif ($@) {
        die $@;   # re-throw everything else
    }

    return $result;
}

sub log_v {
    my ($msg) = @_;
    return unless $opt{verbose};
    if ($opt{'log-json'}) {
        my $entry = eval {
            $ENCODER->encode({ ts => time(), level => 'DEBUG', msg => $msg })
        } // '{"level":"DEBUG","msg":"(encode failed)"}';
        print STDERR $entry, "\n";
    } else {
        print STDERR "[verbose] $msg\n";
    }
}

sub print_stats {
    my ($bytes, $method, $count) = @_;
    return unless $opt{stats};
    my $elapsed = $HAS_HIRESTIME
        ? sprintf("%.4fs", Time::HiRes::time() - $t0)
        : sprintf("%ds",   time() - $t0);
    if ($opt{'log-json'}) {
        my $entry = eval {
            $ENCODER->encode({
                ts          => time(),
                level       => 'STATS',
                input_bytes => $bytes,
                method      => $method,
                found       => $count,
                elapsed     => $elapsed,
            });
        } // '{"level":"STATS","msg":"(encode failed)"}';
        print STDERR $entry, "\n";
    } else {
        printf STDERR "[stats] input=%d bytes  method=%s  found=%d  time=%s\n",
            $bytes, $method, $count, $elapsed;
    }
}

sub parse_size {
    my ($val) = @_;
    return 0 unless $val;
    my %mult = (k => 1024, m => 1024**2, g => 1024**3);
    $val =~ /\A (\d+(?:\.\d+)?) ([kmg])? \z/xi
        or die "json-extract.pl: invalid size value '$val'\n";
    return int($1 * ($mult{lc($2 // '')} // 1));
}

# ===========================================================================
# Usage
# ===========================================================================
sub usage {
    my ($code) = @_;
    print STDERR <<'USAGE';
Usage: json-extract.pl [options] [file]

Extract valid JSON from noisy LLM output.
Pipeline: wrapper tags => code fences => brace scanning => full-input fallback.
Default: picks the LARGEST valid JSON found (beats chatty preambles).

Extraction:
  --extract <mode>      Strategy: smart (default) | fences | braces
  --largest             Pick the largest valid JSON found  [default: ON]
  --no-largest          Pick the leftmost (first) valid JSON instead
  --all                 Extract ALL valid top-level JSON structures
  --strict              Entire input must be JSON (exit 2 if not)
  --jsonl               Treat each input line as a separate JSON object

Repair:
  --tolerant            Strip // # /* */ comments, trailing commas, smart quotes,
                        and common HTML entities (may introduce structural chars)
  --repair              --tolerant + quote bare keys + fix single-quoted strings
                        CAUTION: best-effort; may alter values inside strings
  --recover             Try to close truncated JSON by appending missing } / ]
                        CAUTION: best-effort; may change semantics on cut-off output

Safety:
  --max-size <n>        Reject input larger than n (e.g. 10M, 512k)  [default: 0=off]
  --max-depth <n>       Max JSON nesting depth                        [default: 512]
  --max-attempts <n>    Max parse candidates to try                   [default: 0=off]
  --max-candidate <n>   Skip candidates larger than n bytes           [default: 0=off]
  --max-repair-size <n> Limit expensive tolerant/repair/recovery work [default: 5M]
                        Lower this on memory-constrained systems
                        Smaller of this and --max-candidate wins
  --max-found <n>       Stop after accepting n JSON candidates        [default: 0=off]
  --timeout <n>         Abort extraction after n seconds              [default: 0=off]
                        Approximate only; XS JSON decoding may delay interrupts
  --sanitize            Strip null bytes and ASCII control chars from input

Output:
  --pretty              Pretty-print output JSON
  --fallback-empty      Output {} and exit 1 on failure (safe for pipelines)
  --meta                Emit metadata envelope to STDOUT instead of raw JSON
                        In --jsonl mode, emits one envelope per line

Diagnostics:
  --verbose, -v         Print extraction progress to STDERR
  --stats               Print input size, method, count, elapsed time to STDERR
  --log-json            Emit structured JSON log lines (combine with --verbose/--stats)
  --version             Print version and exit
  --help, -h            Show this help

Exit codes:
  0  JSON found and printed
  1  No valid JSON found
  2  Bad input / --strict failure / bad options
  3  Timeout exceeded
  4  Input exceeds --max-size

Examples:
  echo 'Sure! Here: {"key":"val"}' | perl json-extract.pl
  echo '<json>{"key":"val"}</json>' | perl json-extract.pl
  echo '~~~json\n{"key":"val"}\n~~~' | perl json-extract.pl
  perl json-extract.pl --repair --pretty chatty_llm.txt
  perl json-extract.pl --recover response.txt
  perl json-extract.pl --meta response.txt
  perl json-extract.pl --jsonl --meta lines.txt
  perl json-extract.pl --all --no-largest concatenated.txt
  perl json-extract.pl --timeout 10 --max-size 50M huge.txt
  perl json-extract.pl --fallback-empty --repair response.txt | process.sh
  perl json-extract.pl --verbose --log-json --stats debug.txt 2>run.log
USAGE
    exit $code;
}
