---
title: Noise Collections
---

# Noise Collections

Every vector database and the dev workstation's filesystem include benign, non-sensitive content alongside the sensitive data. These noise collections test aipostex's ability to differentiate signal from noise — a critical capability since real-world environments contain far more benign data than secrets.

---

## Purpose

Noise data serves two functions in the lab:

1. **False-positive testing** — The scoring system's strict mode checks whether aipostex flags noise collections as containing sensitive data. Reporting benign public content as a finding is a false positive.
2. **Realistic density** — Production vector databases and developer filesystems are mostly non-sensitive. A tool that can't distinguish a public API reference from a leaked credential isn't useful in the real world.

---

## ChromaDB: public-documentation

**Host:** ailab-ml (172.16.50.20:8000)

5–8 documents of benign reference material:

- Open-source library documentation (usage guides, API references)
- Public API references for common services
- Marketing copy and product descriptions

No credentials, PII, connection strings, or internal hostnames. All content is the type of documentation that would legitimately appear in a knowledge base used for RAG.

---

## Weaviate: PublicKnowledge

**Host:** ailab-ds (172.16.50.30:8080)

A Weaviate class containing:

- Public dataset descriptions (Kaggle-style dataset cards)
- Wikipedia-style articles on general topics

No sensitive data. The class uses the same schema structure as the sensitive `ResearchDocument` and `TeamCommunication` classes, so aipostex must inspect the actual content rather than relying on schema-level heuristics.

---

## Qdrant: public-faq

**Host:** ailab-ds (172.16.50.30:6333)

A Qdrant collection containing:

- Generic Q&A pairs (product FAQ, onboarding questions)
- Publicly available information with no credentials or PII

The collection sits alongside `product-catalog` and `security-findings` in the same Qdrant instance. aipostex must enumerate all three collections and correctly identify that only two contain sensitive data.

---

## Filesystem: Noise Files

**Host:** ailab-dev (172.16.50.10)

Three files in `/home/devuser/projects/chatbot-prototype/`:

| File | Contents |
|---|---|
| `.env.example` | Placeholder values: `YOUR_OPENAI_KEY_HERE`, `YOUR_ANTHROPIC_KEY_HERE`. Template file, not real credentials. |
| `requirements.txt` | Benign Python dependency list: `langchain`, `openai`, `chromadb`, `python-dotenv`, etc. |
| `README.md` | Standard project readme with setup instructions. No credentials. |

These files sit in the same directory as the real `.env` file containing actual (fake) API keys. aipostex should flag the `.env` file and ignore the `.env.example`, `requirements.txt`, and `README.md`.

---

## Scoring Impact

In **standard mode**, the scoring system only checks for true positives — did aipostex find the planted sensitive data? Noise collections are ignored.

In **strict mode**, the scoring system additionally checks for false positives. If aipostex reports a finding from `public-documentation`, `PublicKnowledge`, `public-faq`, or any of the filesystem noise files, it incurs a penalty. This rewards precision alongside recall.
