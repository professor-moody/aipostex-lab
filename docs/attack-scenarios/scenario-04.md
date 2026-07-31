# Scenario 04: Vector Database PII Extraction

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~20 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-ml:8000 (ChromaDB), ailab-ds:6333 (Qdrant)

## Background

Vector databases are the memory layer of RAG applications: they store embedded documents that an
LLM retrieves at query time to ground its answers. Alongside each embedding they keep the source
text, so a RAG store usually holds full-text chunks of exactly the sensitive material the app was
built to reason over: internal wikis, customer records, financial data, PII. Unlike traditional
databases, vector stores are optimized for similarity search and rarely have row-level access
controls. In the lab, ChromaDB (`ailab-ml:8000`) and Qdrant (`ailab-ds:6333`) both run real and
unauthenticated, which mirrors the field reality that RAG stores are new and rarely locked down.

### Why an attacker cares

There are two directions of value, and both are live here. The first is exfiltration: the documents
are real corporate data, so pulling them back reconstructs the organization's knowledge base and
hands you PII and secrets at scale. The second is poisoning: because the LLM retrieves from this
store at query time, an attacker who writes a malicious document turns the RAG pipeline into an
indirect prompt-injection channel that persists. Every future user query that matches the poisoned
chunk pulls the attacker's content into the model's context.

### How this connects to the rest of the estate

This scenario is the read half (`search-sensitive`), which surfaces the real PII and any credentials
stored in document metadata. The write half is `inject --collection <c> --payload <p>
--verify-persist`, covered in Scenario 07, which confirms a poisoned document is written and
survives a re-read. Credentials found embedded in document metadata are ordinary loot: they feed the
same credential reuse that the ML-platform scenarios exploit.

## Objective

Extract stored documents and PII from ChromaDB and Qdrant vector databases.

## Commands

```bash
# Exploit ChromaDB on the ML platform host
aipostex vectordb --type chromadb --target 172.16.50.20:8000 search-sensitive

# Exploit Qdrant on the data science host
aipostex vectordb --type qdrant --target 172.16.50.30:6333 search-sensitive
```

## Expected Finding

**ChromaDB (ailab-ml:8000):**
- Collection listing reveals RAG document stores
- Stored documents contain PII: names, email addresses, internal project details
- API keys embedded in document metadata

**Qdrant (ailab-ds:6333):**
- Points (stored vectors) contain payload data with sensitive content
- Collection metadata reveals purpose (e.g., "customer-support-embeddings")

Example finding:
```json
{
  "finding_type": "sensitive_data",
  "service": "chromadb",
  "detail": "PII found in stored documents",
  "sample": "Customer: John Smith, email: jsmith@acme.corp..."
}
```

**Landed grading:** `search-sensitive` lands `read-confirmed` (real PII/secrets read out of the
store). The paired `inject --verify-persist` write path lands `influenced` when the poison is
accepted and `takeover-capable` when a re-read confirms it persists.

**Scoring objective:** At least one ChromaDB collection and one Qdrant collection contain extractable PII or credentials.

## Real-World Impact

Vector databases are the hidden data store behind every RAG application. They often contain
full-text copies of documents that were never meant to be directly accessible. Attackers who reach a
ChromaDB or Qdrant instance can reconstruct entire document sets, extract PII at scale, and
understand an organization's proprietary knowledge base. The poisoning direction is quieter and
arguably worse: it plants attacker-controlled text that the LLM will retrieve and act on for every
matching query, with no further access required.

## Follow-On

- [Scenario 07](scenario-07.md): Poison these vector stores to manipulate RAG outputs
- [Scenario 12](scenario-12.md): Use extracted PII as part of a multi-vector campaign
