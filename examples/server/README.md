# Example Go Servers

These are intentionally simple wrappers around `llm-json-extract.pl`.

- `nethttp/`: plain Go `net/http`
- `nanite/`: Nanite router example
- `python/`: Python `http.server` example
- `node/`: Node.js `http` example
- `ts/`: TypeScript (`tsx`) example

Both expose:
- `GET /health`
- `POST /extract` with JSON body: `{"raw":"<llm text>"}`

They execute:

```text
perl <extractor> --meta --fallback-empty --timeout 2 --max-size 10M --max-candidate 2M --max-repair-size 1M
```

## Extractor Path

Set `EXTRACTOR_PATH` to the script path if needed.

Default in both examples is:

```text
../../../llm-json-extract.pl
```

(from each example directory)

## Run net/http Example

```bash
cd examples/server/nethttp
go run .
```

Test:

```bash
curl -sS http://localhost:8080/health | jq .

curl -sS http://localhost:8080/extract \
  -H 'content-type: application/json' \
  --data-binary @- <<'JSON' | jq .
{"raw":"Here is data: {\"ok\":true,\"id\":123}"}
JSON
```

## Run Nanite Example

```bash
cd examples/server/nanite
go get github.com/xDarkicex/nanite@latest
go run .
```

Test:

```bash
curl -sS http://localhost:8081/health | jq .

curl -sS http://localhost:8081/extract \
  -H 'content-type: application/json' \
  --data-binary @- <<'JSON' | jq .
{"raw":"analysis... ```json\\n{\"project\":\"x\",\"ok\":true}\\n```"}
JSON
```

## Run Python Example

```bash
cd examples/server/python
python3 server.py
```

Test:

```bash
curl -sS http://localhost:8082/health | jq .

curl -sS http://localhost:8082/extract \
  -H 'content-type: application/json' \
  --data-binary @- <<'JSON' | jq .
{"raw":"Here is data: {\"ok\":true,\"stack\":\"python\"}"}
JSON
```

## Run Node Example

```bash
cd examples/server/node
npm run start
```

Test:

```bash
curl -sS http://localhost:8083/health | jq .

curl -sS http://localhost:8083/extract \
  -H 'content-type: application/json' \
  --data-binary @- <<'JSON' | jq .
{"raw":"analysis... ```json\\n{\"ok\":true,\"stack\":\"node\"}\\n```"}
JSON
```

## Run TypeScript Example

```bash
cd examples/server/ts
npm install
npm run start
```

Optional type-check:

```bash
npm run check
```

Test:

```bash
curl -sS http://localhost:8084/health | jq .

curl -sS http://localhost:8084/extract \
  -H 'content-type: application/json' \
  --data-binary @- <<'JSON' | jq .
{"raw":"Here is mixed output {\"ok\":true,\"stack\":\"ts\"} and extra text"}
JSON
```

## Notes

- This is example code only.
- No auth, no rate limiting, no production hardening.
- Security controls and deployment policy are intentionally left to the user.
