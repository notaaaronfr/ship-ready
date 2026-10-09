# Security Review

## Contents
1. Method: trust boundaries and source → sink tracing
2. OWASP Top 10:2025 → what to check in code
3. CWE Top 25 (2025): the ones agents miss
4. Code that calls LLMs or runs agents (OWASP LLM Top 10 2025 / Agentic 2026)
5. Supply chain
6. Reporting security findings

---

## 1. Method

Security findings are only real if a path exists from an **untrusted source** to a
**dangerous sink** without adequate control in between. Trace it.

| Source | Trust |
|---|---|
| HTTP params, headers, cookies, bodies, uploaded files, webhooks | Attacker-controlled |
| Queue messages, DB rows written by users, third-party API responses | Attacker-influenced |
| LLM output, tool output, retrieved documents (RAG) | Attacker-influenced (prompt injection) |
| Env vars, config files, server-side constants | Server-controlled |

| Sink | Risk |
|---|---|
| SQL / NoSQL / LDAP / XPath query builders | Injection |
| Shell, `subprocess`, `exec`, `eval`, template engines | Command / code injection |
| File paths, archive extraction | Path traversal, zip-slip |
| Outbound HTTP with user-supplied URL | SSRF |
| HTML/JS output | XSS |
| Deserializers (`pickle`, Java serialization, YAML `load`) | Remote code execution |
| Authorization decisions | Broken access control |
| Logs | Log injection, secret/PII leakage |

For each P0/P1: name the source, the sink, the path (file:line hops), and why existing
controls (framework escaping, ORM parameterization, middleware) do or don't stop it.
If the framework already neutralizes it, it's not a finding.

## 2. OWASP Top 10:2025 → code checks

| # | Category | Check in code |
|---|---|---|
| A01 | Broken Access Control (incl. SSRF) | Every handler checks **authorization**, not just authentication; object ownership checked (no IDOR); deny by default; outbound URLs allow-listed |
| A02 | Security Misconfiguration | Debug off; secure headers; CORS not `*` with credentials; no default credentials; least-privilege IAM |
| A03 | Software Supply Chain Failures | See §5 |
| A04 | Cryptographic Failures | No home-made crypto; TLS verification on; modern algorithms (AES-GCM, Argon2/bcrypt/scrypt for passwords); secrets from a secret manager |
| A05 | Injection | Parameterized queries; no string-built shell commands; context-aware output encoding |
| A06 | Insecure Design | Rate limits; abuse cases considered; limits on sizes, counts and costs |
| A07 | Authentication Failures | Session rotation on login; MFA hooks; constant-time comparison; lockout/backoff |
| A08 | Software or Data Integrity Failures | Signed updates/artifacts; no unsafe deserialization of untrusted data |
| A09 | Security Logging & Alerting Failures | Security events logged with context; no secrets/PII in logs; alerts exist |
| A10 | Mishandling of Exceptional Conditions | **Fail closed**: no `except: pass`, no default-allow on error, no fallback that skips a check |

Source: https://owasp.org/Top10/2025/

## 3. CWE Top 25 (2025): highest-yield checks

Top of the list: CWE-79 XSS, CWE-89 SQL injection, CWE-352 CSRF, CWE-862 Missing
Authorization, CWE-787/125 out-of-bounds write/read, CWE-22 path traversal,
CWE-416 use-after-free, CWE-78 OS command injection, CWE-94 code injection.

**The authorization cluster AI code routinely misses:** CWE-862 (missing authz),
CWE-863 (incorrect authz), CWE-639 (IDOR: user-controlled key), CWE-306 (missing
authentication for a critical function), CWE-284. Check every endpoint that reads or
mutates an object: *does it verify that the caller may act on **this** object?*

Also: CWE-502 deserialization, CWE-918 SSRF, CWE-770 allocation without limits
(unbounded uploads, pagination, regex, recursion).

Source: https://cwe.mitre.org/top25/

## 4. Code that calls LLMs or runs agents

| Risk | Rule |
|---|---|
| Prompt injection (LLM01 / ASI01 goal hijack) | Content from users, web pages, files or tools can carry instructions. Never let it select tools or targets without validation |
| Improper output handling (LLM05) | Treat model output as untrusted input: validate against a schema, encode before rendering, never pass to `eval`, shell or SQL |
| Excessive agency (LLM06 / ASI02 tool misuse) | Least-privilege tools and tokens; allow-list actions; human confirmation for irreversible or external actions |
| Sensitive information disclosure (LLM02, LLM07) | No secrets in prompts or system prompts; redact PII before sending |
| Unbounded consumption (LLM10) | Token, cost, rate and recursion limits; timeouts on every model call |

Sources: https://genai.owasp.org/llm-top-10/ ; OWASP Top 10 for Agentic Applications (2026).

## 5. Supply chain

- **Verify every new dependency exists and is legitimate** before adding it:
  `scripts/verify_package.sh`. In one study (USENIX Security 2025), ~20% of packages
  suggested by code models did not exist, and the same fake names recur, so attackers
  can register them ("slopsquatting"). Red flags: created in the last 90 days, few
  downloads, no repository link, a name one character off a popular package.
- Lockfiles committed, with hashes where the ecosystem supports it.
- CI: third-party actions pinned by full commit SHA; `permissions:` set to least
  privilege; no `pull_request_target` with checkout of untrusted code.
- Run dependency audit (`pip-audit`, `npm audit`, `osv-scanner`, `govulncheck`, `cargo audit`).
- For releases: SBOM (CycloneDX/SPDX) and signed provenance (SLSA Build L2+).
  OpenSSF Scorecard is a quick external check of repo hygiene.

## 6. Reporting

Each security finding: CWE ID, OWASP category, source → sink path with file:line,
exploit sketch in one sentence, fix, and the test proving the fix. Where the org uses
OWASP ASVS 5.0, cite the requirement ID (e.g. `v5.0.0-1.2.5`) in the finding and ADR.
