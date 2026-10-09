# <Project Name>

> One sentence: what this does and for whom.

[![CI](<badge-url>)](<ci-url>) Coverage: <x>% · Owner: <team / contact>

## Overview
- **Problem it solves:** …
- **Key responsibilities:** …
- **Non-goals:** …

## Architecture
```
<client> → api/ → services/ → domain/
                      ↓
                  adapters/ → <DB / queue / external API>
```
Key decisions are recorded in [`docs/adr/`](docs/adr/).

## Quick start
```bash
git clone <repo> && cd <repo>
cp .env.example .env          # fill in values, see Configuration
make setup                    # install dependencies + pre-commit hooks
make run                      # start locally on http://localhost:<port>
```

## Development
| Command | What it does |
|---|---|
| `make test` | Unit + integration tests with coverage |
| `make lint` | Formatter check, linter, type checker |
| `make check` | Full quality gate (what CI runs) |
| `make bench` | Performance benchmarks |

## Configuration
| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Connection string |
| `LOG_LEVEL` | no | `INFO` | `DEBUG`/`INFO`/`WARNING`/`ERROR` |

## Testing strategy
- Unit tests: `tests/unit` — pure logic, no I/O.
- Integration tests: `tests/integration` — real DB via Testcontainers.
- E2E: `tests/e2e` — critical journeys only.
- Quality gates: see `.github/workflows/ci.yml`.

## Operations
- **Deploy:** …
- **Monitoring / dashboards:** …
- **Alerts and runbook:** …
- **Rollback:** …

## Contributing
Branch from `main`, Conventional Commits, PR template checklist, one approval + green CI to merge.
