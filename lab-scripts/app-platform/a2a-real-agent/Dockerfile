# Real A2A agent (official a2a-sdk) — used by the dev-machine `sandbox` harness to
# validate aipostex's A2A probe verbs against true SDK behaviour. There is no
# pullable image for the SDK agent, so it is built from this context.
# A2A_MODE ("" | vuln | secure) selects the honest / deliberately-weak / hardened
# variant at run time (see server.py); the image is identical for all three.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

EXPOSE 8103

CMD ["python", "server.py"]
