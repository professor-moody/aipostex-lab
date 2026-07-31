from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_service_catalog_has_expected_entries():
    result = subprocess.run(
        [
            "bash",
            "-lc",
            "source lab-scripts/lib/inventory.sh && "
            "source lab-scripts/lib/service-catalog.sh && "
            "inventory_service_health_checks",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) >= 24
    assert any("ailab-ml|8000|/api/v1/heartbeat|nanosecond|ChromaDB|" == line for line in lines)
    assert any("ailab-ml|5000|/health|OK|MLflow backend|" == line for line in lines)
    assert any("ailab-ds|5000|/health|OK|MLflow auth gateway|" == line for line in lines)
    assert any("ailab-app|8180|/health|ok|HF TGI gateway|" == line for line in lines)
    assert any("ailab-app|8501|/_stcore/health|ok|Streamlit|" == line for line in lines)
    assert any("ailab-ml|3333|/healthz|healthy|BentoML mock|" == line for line in lines)
    assert any("ailab-ml|8081|/models|models|TorchServe mock|" == line for line in lines)
    assert any("ailab-ml|9000|/pipeline/|pipeline|Kubeflow mock|" == line for line in lines)
    assert any("ailab-ml|8501|/v1/models/acme-fraud-scorer|model_version_status|TF Serving mock|" == line for line in lines)
