#!/usr/bin/env node
const http = require('http');
const { execFile } = require('child_process');

const HOST = '0.0.0.0';
const PORT = 8083;
const EXTRACTOR_PATH = process.env.EXTRACTOR_PATH || '../../../llm-json-extract.pl';

function writeJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return writeJson(res, 200, { ok: true });
  }

  if (req.method === 'POST' && req.url === '/extract') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });

    req.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body || '{}');
      } catch (_) {
        return writeJson(res, 400, { error: 'invalid_json_body' });
      }

      const raw = typeof payload.raw === 'string' ? payload.raw : '';
      if (!raw.trim()) {
        return writeJson(res, 400, { error: 'raw_is_required' });
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
          return writeJson(res, 502, {
            error: 'extract_exec_failed',
            details: err.message,
            exit_code: err.code,
            stderr,
            extractor: (stdout || '').trim(),
          });
        }

        try {
          JSON.parse(stdout);
        } catch (_) {
          return writeJson(res, 502, {
            error: 'extractor_returned_non_json',
            stderr,
            extractor: (stdout || '').trim(),
          });
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
  console.log(`node example listening on ${HOST}:${PORT}`);
});
