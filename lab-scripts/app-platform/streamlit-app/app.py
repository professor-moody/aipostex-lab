#!/usr/bin/env python3
import pandas as pd
import streamlit as st


st.set_page_config(page_title="ML Model Monitor", layout="wide")

st.title("ML Model Monitor")
st.caption("Shared AI app box dashboard for fingerprinting and unauthenticated UI discovery.")

left, right = st.columns(2)

with left:
    st.subheader("Deployment Health")
    st.metric("Healthy endpoints", 7, delta=2)
    st.metric("Prompt incidents", 3, delta=-1)

with right:
    st.subheader("Operator Controls")
    st.selectbox("Environment", ["production", "staging", "canary"])
    st.slider("Latency budget (ms)", min_value=50, max_value=800, value=180)

st.subheader("Recent Evaluations")
st.dataframe(
    pd.DataFrame(
        [
            {"model": "langserve-router", "status": "healthy", "latency_ms": 182},
            {"model": "support-summarizer", "status": "warning", "latency_ms": 241},
            {"model": "incident-annotator", "status": "healthy", "latency_ms": 167},
        ]
    ),
    use_container_width=True,
)

st.button("Trigger smoke check")
st.text_area("Operator note", "Shared app box exposes Streamlit without auth.")

