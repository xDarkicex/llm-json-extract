requires 'perl', '5.034000';

# Runtime JSON support: script can run with JSON::PP (core) and optionally
# uses JSON::MaybeXS when available for performance.
requires 'JSON::PP';
recommends 'JSON::MaybeXS';
recommends 'Cpanel::JSON::XS';

on 'test' => sub {
  requires 'Test::More';
};
