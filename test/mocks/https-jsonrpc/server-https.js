const https = require('https');
const fs = require('fs');

const PORT = process.env.PORT ? Number(process.env.PORT) : 38899;
const HEALTH = process.env.HEALTH || 'ok';
const NAME = process.env.NAME || 'mock-https';
const CERT_DIR = process.env.CERT_DIR || '/etc/certs';

const options = {
  key: fs.readFileSync(`${CERT_DIR}/server.key`),
  cert: fs.readFileSync(`${CERT_DIR}/server.crt`)
};

const server = https.createServer(options, (req, res) => {
  if (req.method !== 'POST') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    return res.end('mock https json-rpc');
  }
  let body = '';
  req.on('data', (chunk) => (body += chunk));
  req.on('end', () => {
    try {
      const json = JSON.parse(body || '{}');
      if (json.method === 'getHealth') {
        res.writeHead(200, { 'content-type': 'application/json' });
        return res.end(JSON.stringify({ jsonrpc: '2.0', id: json.id ?? 1, result: HEALTH === 'ok' ? 'ok' : 'unhealthy' }));
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ jsonrpc: '2.0', id: json.id ?? 1, result: { method: json.method, server: NAME } }));
    } catch (e) {
      res.writeHead(400, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: 'bad json' }));
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Mock HTTPS JSON-RPC listening on ${PORT} (${NAME}), health=${HEALTH}`);
});

