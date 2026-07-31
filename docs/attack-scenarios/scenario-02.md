# Scenario 02: LLM Gateway Config Extraction

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Beginner
**Time:** ~10 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-ml:4000 (LiteLLM Proxy)

## Background

LiteLLM is the standard proxy that gives a team one OpenAI-compatible API over many model backends.
It routes requests to providers like Anthropic, HuggingFace, Azure, and AWS Bedrock, and teams
centralize their keys and routing rules in it precisely so the rest of the stack only has to know
one endpoint. In the lab it runs on `ailab-ml:4000` (with an authed variant on `:4001`), real
LiteLLM, deployed without authentication in front of the config.

### Why an attacker cares

Because a team centralizes keys here, the gateway is a single point where every provider credential
converges. Reading its configuration is LLM-jacking waiting to happen: you learn which backends
exist, which models map to which provider, and you recover the keys that pay for them. From there
an attacker can generate text on the company's bill, exfiltrate the routing logic that reveals how
the AI product is built, and reach fine-tuned models sitting behind the proxy. The master key is
also siftable, which turns config disclosure into real inference through the looted key.

### How this connects to the rest of the estate

Config extraction is the read half. The paired capability is `openai-compat generate`, which takes
a looted key and runs genuine input-dependent inference against the proxy, moving the finding from
`read-confirmed` (you read the keys) to `execution-confirmed` (you used one). The provider keys you
recover here are also loot in their own right: they are live credentials to external services, not
just lab artifacts.

## Objective

Extract API keys, model configurations, and backend provider details from the LiteLLM proxy.

## Commands

```bash
# Fingerprint the LiteLLM instance
aipostex discover network --target 172.16.50.20:4000 --discovery-only

# Extract configuration and API keys (read-confirmed)
aipostex litellm --target 172.16.50.20:4000 config-extract

# Run real inference through the unauthenticated proxy (execution-confirmed)
aipostex openai-compat --target http://172.16.50.20:4000 \
  generate --prompt "incident response" --force-exploit
```

## Expected Finding

The LiteLLM proxy exposes its full configuration including:

- **API Keys:** OpenAI, Anthropic, Azure, and AWS Bedrock keys configured as backend providers
- **Model routing table:** Which models map to which providers
- **Rate limits and spend tracking:** Per-key usage data

Example finding:
```json
{
  "finding_type": "api_key",
  "service": "litellm",
  "key_type": "openai_api_key",
  "value": "sk-proj-fake-..."
}
```

**Landed grading:** `config-extract` lands `read-confirmed` (you read real key material out of the
config). `openai-compat generate` lands `execution-confirmed` (real,
input-dependent model output through the proxy).

**Scoring objective:** At least 4 API keys extracted from the LiteLLM configuration (OpenAI, Anthropic, Azure, Bedrock).

## Real-World Impact

LLM gateways are becoming the central nervous system of enterprise AI. A compromised LiteLLM proxy
gives an attacker access to every LLM provider the enterprise uses. They can generate text at the
company's expense, exfiltrate the routing logic, and potentially reach fine-tuned models behind the
gateway. Because the gateway concentrates keys by design, one weak deployment leaks the whole
provider set at once.

## Follow-On

- [Scenario 06](scenario-06.md): Harvest credentials from more ML platform services
- [Scenario 08](scenario-08.md): Chain these keys with other findings
