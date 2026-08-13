---
title: Honesty Controls
---

# Honesty Controls

## What They Are

Four services — three on `ailab-dev`, one on `ailab-ds` — that **are not targets**. They exist so the
[precision benchmark](../../scoring/benchmark.md) has a negative side: a service that refuses
an unauthenticated caller, against which any success claim from aipostex is a false positive.

Everything else in this lab is deliberately weak. These are deliberately *correct* — and
they are just as necessary, because a scanner that only ever meets vulnerable services can
never be shown to exercise restraint.

| Service | Host | Port | Unit | Refuses with |
|---|---|---|---|---|
| Jupyter Lab (token-enforced) | ailab-dev | `8890` | `jupyter-secure.service` | `403` |
| MCP server (bearer-enforced) | ailab-dev | `3003` | `acme-mcp-secure.service` | `401` + `WWW-Authenticate` |
| Gradio app (login-enforced) | ailab-dev | `7861` | `gradio-secure.service` | `401` |
| Qdrant (API-key enforced) | ailab-ds | `6335` | `qdrant-secure.service` | `401` |

Each uses the **real product's own** authentication, not a bolted-on proxy:

- **Jupyter** — the same JupyterLab as the target on `:8888`, with its default token
  protection switched back on (`c.IdentityProvider.token`). The open instance is the
  misconfiguration; this one is stock behaviour.
- **MCP** — the same MCP SDK stack (FastMCP, Streamable HTTP at `/mcp`) as `:3000` and
  `:3002`, with the ASGI app wrapped in bearer-token middleware. It answers `401` with a
  `WWW-Authenticate: Bearer` challenge pointing at protected-resource metadata, which is how
  the MCP authorization spec expects a protected resource to behave.
- **Gradio** — the same Gradio framework as the open app on `:7860`, with the framework's own
  `auth=` login enabled. API routes answer `401` without a session.
- **Qdrant** — a second Qdrant instance with Qdrant's own `service.api_key` set, on separate
  storage. Requests without the `api-key` header get `401`.

A fifth pair needs no dedicated service: the key-enforced LiteLLM proxy on `:4001` already
refuses unauthenticated callers, so it serves as the control for the `openai-compat` module.

## Seeded Credentials

Held by a legitimate client, and — as everywhere in this lab — not redacted:

- Jupyter token: `acme-jupyter-9d41f77b`
- MCP bearer: `acme-mcp-prod-7f3a91c4`
- Gradio login: `mluser` / `acme-gradio-6c19d3ba`
- Qdrant api-key: `acme-qdrant-4b8e21fa`

## Correct Tool Behaviour

Against these services aipostex should report the endpoint as reachable and
authentication-enforced, and claim **nothing** beyond that. Concretely:

```bash
# Should report auth enforced, and no access
aipostex mcp --target http://172.16.50.10:3003 auth
aipostex jupyter --target http://172.16.50.10:8890 enum
aipostex gradio --target http://172.16.50.10:7861 enum
aipostex vectordb --target http://172.16.50.30:6335 --type qdrant enum
```

A finding graded above `reachable` against any of these services is a false positive, and
the benchmark counts it as one.

## Keeping Them Honest

`verify-lab.sh` asserts that all four still refuse unauthenticated callers and **fails** if any
stops. This matters more than it looks: if a control silently began answering without
credentials, the benchmark would keep reporting a clean run it had not earned. The control
must be verified, not assumed.
