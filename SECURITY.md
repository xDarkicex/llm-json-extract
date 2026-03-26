# Security Policy

## Supported Versions

Security fixes are applied to the latest released version.

| Version | Supported |
| --- | --- |
| Latest tag | yes |
| Older tags | no |

## Reporting a Vulnerability

Please do not open public issues for security reports.

Send a private report with:
- affected version/tag
- reproduction input or proof-of-concept
- impact assessment
- suggested mitigation (optional)

Contact:
- GitHub Security Advisories (preferred)
- or private email to project maintainer (if configured in repository profile)

## Response Targets

- Initial acknowledgment: within 72 hours
- Triage decision: within 7 days
- Fix + coordinated disclosure target: within 30 days for high severity, when feasible

## Scope Notes

This project is a JSON extraction CLI and does not provide sandboxing for arbitrary untrusted code execution.

Primary security goals:
- bounded parsing behavior
- safe failure modes
- predictable output contracts

Out of scope:
- host-level compromise
- kernel/container escape scenarios
- deployment-specific misconfiguration outside this repository
