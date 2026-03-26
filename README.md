# llm-json-extract

High-assurance JSON extraction for noisy LLM output.

`llm-json-extract.pl` is a deterministic CLI filter that finds JSON inside wrappers, chatty text, or truncated model output and emits valid JSON for pipelines, APIs, and frontend backends.

## Homebrew Install

```bash
brew tap zephyr-systems/llm-json-extract
brew install llm-json-extract
```

## Manual Install

```bash
git clone https://github.com/xDarkicex/llm-json-extract.git
cd llm-json-extract
chmod +x llm-json-extract.pl
sudo install -m 0755 llm-json-extract.pl /usr/local/bin/llm-json-extract
```

Run after manual install:

```bash
llm-json-extract --version
```

## Usage Guide

Most common flow:

```bash
<command that prints LLM output> | llm-json-extract | jq .
```

Reliable stdin paste flow (Linux/macOS, avoids shell quote issues):

```bash
llm-json-extract <<'EOF' | jq .
PASTE LLM OUTPUT HERE
EOF
```

From file:

```bash
llm-json-extract response.txt | jq .
```

Meta envelope mode (recommended for integrations):

```bash
llm-json-extract --meta --fallback-empty --timeout 2 response.txt | jq .
```

## What Problem It Solves

LLM responses often include preambles, markdown fences, XML-ish wrappers, comments, trailing commas, or truncation. This tool provides a bounded, production-oriented extraction path with explicit failure modes.

## Input/Output Contract

Input:
- UTF-8 text from `STDIN` or a file path argument.
- Can contain wrappers (`<json>...</json>`), fences, or mixed noise.

Output:
- On success: valid JSON to `STDOUT`.
- With `--meta`: envelope JSON with extraction metadata and stable error strings.
- With `--fallback-empty`: emits `{}` on failure paths while preserving non-zero exits.

Default extraction order:
1. Wrapper tags
2. Markdown/code fences
3. Brace/bracket scanner
4. Full-input fallback

Default selection policy:
- Largest valid candidate wins (`--largest` is on by default).

## Exit Codes

- `0`: JSON found and emitted
- `1`: no valid JSON found
- `2`: invalid options/input contract failure (`--strict`, bad options, etc.)
- `3`: timeout exceeded
- `4`: input exceeds `--max-size`

## Safety Model

Core safety controls:
- `--max-size`: reject oversized raw input before decode
- `--max-candidate`: skip oversized candidates
- `--max-repair-size`: cap expensive tolerant/repair/recover paths
- `--max-attempts`: bound parse attempts
- `--max-found`: bound accepted candidates
- `--timeout`: alarm-based extraction timeout (best-effort)
- `--sanitize`: remove control characters

Notes:
- Timeouts are approximate, especially with XS decoder internals.
- `--repair` and `--recover` are best-effort transforms and can alter semantics.

## Recommended Production Flags

Conservative pipeline defaults:

```bash
perl llm-json-extract.pl \
  --meta \
  --fallback-empty \
  --max-size 10M \
  --max-candidate 2M \
  --max-repair-size 1M \
  --max-attempts 500 \
  --max-found 20 \
  --timeout 2
```

When strict contracts are required:

```bash
perl llm-json-extract.pl --strict --timeout 1
```

## Examples

Shell pipeline:

```bash
echo 'Answer: {"ok":true}' | perl llm-json-extract.pl
```

Frontend/backend handoff (`--meta` envelope):

```bash
cat llm-response.txt | perl llm-json-extract.pl --meta
```

Batch JSONL normalization:

```bash
cat model-lines.txt | perl llm-json-extract.pl --jsonl --meta
```

Repair/recover (best-effort):

```bash
cat noisy.txt | perl llm-json-extract.pl --repair --recover --pretty
```

Example files in this repo:
- CLI pipeline helper: `examples/pipeline.sh`
- Server wrappers overview: `examples/server/README.md`
- Go `net/http` wrapper: `examples/server/nethttp/main.go`
- Go Nanite wrapper: `examples/server/nanite/main.go`
- Python wrapper: `examples/server/python/server.py`
- Node wrapper: `examples/server/node/server.js`
- TypeScript wrapper: `examples/server/ts/server.ts`

## Tests

Layout:
- `t/00-load.t` syntax/load checks
- `t/01-strict.t` strict mode contract
- `t/02-jsonl.t` JSONL behavior
- `t/03-meta.t` envelope contract
- `t/04-repair.t` tolerant/repair behavior
- `t/05-recover.t` truncation recovery
- `t/06-limits.t` max-size/candidate/repair/found/attempts bounds
- `t/07-timeout.t` timeout behavior (best-effort trigger)
- `t/08-wrapper-tags.t` wrapper extraction edge cases
- `t/09-fixtures.t` golden fixtures under `tests/fixtures/`
- `t/10-property.t` randomized invariant tests

Run tests:

```bash
prove -lr t
```

## CI

GitHub Actions workflow: `.github/workflows/ci.yml`

Current pipeline includes:
- matrix test on macOS + Linux and multiple Perl versions
- syntax check (`perl -c`)
- test suite (`prove -lr t`)
- Linux smoke checks for golden output, noisy input, timeout contract, and meta envelope stability

## Deployment

### One-shot CLI in pipelines

Use the script as a filter, not a daemon, for most workloads.

### systemd service and socket examples

Provided files under `packaging/systemd/`:
- `llm-json-extract.socket`
- `llm-json-extract@.service` (per-connection workers for `Accept=yes`)
- `llm-json-extract.service` (standalone service example)

Install example:

```bash
sudo install -m 0644 packaging/systemd/llm-json-extract.socket /etc/systemd/system/
sudo install -m 0644 packaging/systemd/llm-json-extract@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llm-json-extract.socket
```

Test socket activation:

```bash
printf 'Answer: {"ok":true}' | socat - UNIX-CONNECT:/run/llm-json-extract.sock
```

### systemd hardening posture

The example units include:
- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `PrivateTmp=true`
- `PrivateDevices=true`

Evaluate your final posture with:

```bash
systemd-analyze security llm-json-extract@.service
```

## Threat Model (Short)

Designed to reduce accidental parser failures and unbounded work on hostile/noisy text, not to sandbox arbitrary code execution.

Out of scope:
- malicious kernel-level actors
- full protocol daemon concerns (framing, authn/authz, concurrency control)

## Known Limitations

- Timeout behavior is approximate.
- `--repair` key quoting is heuristic.
- `--recover` appends structural closers and may change meaning.
- This project is a CLI filter, not an HTTP server or socket daemon.

## Compatibility

CI targets Perl `5.34`, `5.36`, `5.38`, and `5.40`.

## Versioning and Releases

- Use semantic versioning tags (`vMAJOR.MINOR.PATCH`).
- Tag `v1.0.0` after fixture corpus and behavior contracts are stable.

## Repository Layout

- `llm-json-extract.pl`
- `README.md`
- `LICENSE`
- `.github/workflows/ci.yml`
- `t/`
- `tests/fixtures/`
- `examples/`
- `packaging/systemd/`
- `tools/`
