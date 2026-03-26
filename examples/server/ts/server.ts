import http from 'node:http';
import { execFile } from 'node:child_process';

const HOST = '0.0.0.0';
const PORT = 8084;
const EXTRACTOR_PATH = process.env.EXTRACTOR_PATH || '../../../llm-json-extract.pl';

type ErrorResponse = { error: string; [key: string]: unknown };

type RequestPayload = {
  raw?: unknown;
};

function writeJson(res: http.ServerResponse, status: number, payload: unknown): void {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    writeJson(res, 200, { ok: true });
    return;
  }

  if (req.method === 'POST' && req.url === '/extract') {
    let body = '';

    req.on('data', (chunk) => {
      body += chunk;
    });

    req.on('end', () => {
      let payload: RequestPayload;
      try {
        payload = JSON.parse(body || '{}') as RequestPayload;
      } catch {
        writeJson(res, 400, { error: 'invalid_json_body' });
        return;
      }

      const raw = typeof payload.raw === 'string' ? payload.raw : '';
      if (!raw.trim()) {
        writeJson(res, 400, { error: 'raw_is_required' });
        return;
      }

      const args = [
        EXTRACTOR_PATH,
        '--meta',
        '--fallback-empty',
        '--timeout', '2',
        '--max-size', '10M',
        '--max-candidate', '2M',
        '--max-repair-size', '1M',
      ];

      const child = execFile('perl', args, { timeout: 5000, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
        if (err) {
          writeJson(res, 502, {
            error: 'extract_exec_failed',
            details: err.message,
            exit_code: (err as NodeJS.ErrnoException).code,
            stderr,
            extractor: (stdout || '').trim(),
          } satisfies ErrorResponse);
          return;
        }

        try {
          JSON.parse(stdout);
        } catch {
          writeJson(res, 502, {
            error: 'extractor_returned_non_json',
            stderr,
            extractor: (stdout || '').trim(),
          } satisfies ErrorResponse);
          return;
        }

        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(stdout);
      });

      child.stdin.write(raw);
      child.stdin.end();
    });

    return;
  }

  writeJson(res, 404, { error: 'not_found' });
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`ts example listening on ${HOST}:${PORT}`);
});
