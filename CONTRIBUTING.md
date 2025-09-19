Contributing

Thanks for your interest in contributing! Please follow these guidelines:

Prerequisites

- Docker Desktop or Docker Engine + Compose
- Bash, curl, nc; optional: grpcurl

Development

- Clone and run locally:
  - Start stack: `docker compose up -d --build`
  - Stats UI: http://localhost:8404 (admin/admin)
  - JSON-RPC: http://localhost:8899, gRPC: localhost:10000

Testing

- Run local tests:
  - `cd test && bash ./run.sh`
  - This uses Dockerized mock servers and scenario env files.

Pull Requests

- Fork the repo and create a feature branch
- Keep changes focused; include tests when relevant
- Update README if user-facing behavior changes

Security

- Do not commit secrets (.env is gitignored). Report vulnerabilities privately.

License

- By contributing, you agree that your contributions will be licensed under the MIT License.

