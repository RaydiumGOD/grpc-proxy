const http = require('http');

const PORT = process.env.PORT ? Number(process.env.PORT) : 8899;
const HEALTH = process.env.HEALTH || 'ok'; // ok or unhealthy
const NAME = process.env.NAME || 'mock-1';

const server = http.createServer((req, res) => {
  if (req.method !== 'POST') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    return res.end('mock json-rpc');
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
      // Echo method name and mock name
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ jsonrpc: '2.0', id: json.id ?? 1, result: { method: json.method, server: NAME } }));
    } catch (e) {
      res.writeHead(400, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: 'bad json' }));
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Mock JSON-RPC listening on ${PORT} (${NAME}), health=${HEALTH}`);
});

