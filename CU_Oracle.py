"""The Credit Union Oracle — Streamlit in Snowflake chat app.

Questions go straight to a Cortex Agent (SNOWFLAKE.CORTEX.AGENT_RUN) whose only
tool is Cortex Analyst over the CU_ORACLE_SEMANTIC semantic view. Cortex plans,
queries the semantic view, and writes the answer; this app only renders it.
"""
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

SEMANTIC_VIEW = "CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_SEMANTIC"
WAREHOUSE = "STREAMLIT_WH"          # warehouse Cortex uses to run its queries
ORCHESTRATION_MODEL = "auto"        # or pin a model, e.g. "claude-sonnet-4-5"
IMAGE_PATH = "@cu_oracle_agent_db.analytics.STG_IMAGES/Socrates.png"
MAX_HISTORY_MESSAGES = 10           # prior chat messages sent back for follow-up context

RESPONSE_INSTRUCTIONS = """You are the Credit Union Oracle, an expert on US credit unions and an
enthusiastic advocate for credit unions and cooperative finance.
- Answer ONLY with facts returned by the cu_oracle tool. Never use outside knowledge or invent figures.
- Lead with the direct answer, then supporting detail. Be concise.
- Cite specific credit union names, numbers, and dates from the data.
- Write dollar amounts readably (e.g., $203.6 billion) and use thousands separators for counts.
- If the data does not contain the answer, say so plainly instead of guessing."""

ORCHESTRATION_INSTRUCTIONS = """Always use the cu_oracle tool to answer questions about credit unions.
Do not answer from general knowledge. Unless the user asks otherwise, consider only active credit unions.
Politely decline questions unrelated to US credit unions, and dismiss questions about commercial banks
as unworthy of the CU Oracle's compute tokens."""

TOOL_NAME = "cu_oracle"
TOOL_DESCRIPTION = (
    "Credit union contact, demographic, financial, and operational data from NIMBLE "
    "(America's Credit Unions' association management software), NCUA call report "
    "financials, and the NCUA branch file."
)


# ---------------------------------------------------------------------------
# Cortex Agent call
# ---------------------------------------------------------------------------
def build_request(history: list[dict], question: str) -> dict:
    """Assemble the AGENT_RUN request body: prior text turns + the new question."""
    messages = []
    for msg in history[-MAX_HISTORY_MESSAGES:]:
        text = msg.get("text", "").strip()
        if text:
            messages.append({"role": msg["role"], "content": [{"type": "text", "text": text}]})
    messages.append({"role": "user", "content": [{"type": "text", "text": question}]})

    return {
        "models": {"orchestration": ORCHESTRATION_MODEL},
        "instructions": {
            "response": RESPONSE_INSTRUCTIONS,
            "orchestration": ORCHESTRATION_INSTRUCTIONS,
        },
        "messages": messages,
        "tools": [{"tool_spec": {
            "type": "cortex_analyst_text_to_sql",
            "name": TOOL_NAME,
            "description": TOOL_DESCRIPTION,
        }}],
        "tool_resources": {TOOL_NAME: {
            "semantic_view": SEMANTIC_VIEW,
            "execution_environment": {"type": "warehouse", "warehouse": WAREHOUSE},
        }},
    }


def ask_oracle(session, history: list[dict], question: str) -> dict:
    body = json.dumps(build_request(history, question))
    raw = session.sql("SELECT SNOWFLAKE.CORTEX.AGENT_RUN(?)", params=[body]).collect()[0][0]
    return json.loads(raw)


# ---------------------------------------------------------------------------
# Response parsing
# ---------------------------------------------------------------------------
def _fix_mojibake(text: str) -> str:
    """Repair UTF-8 text that was decoded as cp1252 somewhere in transit (e.g. 'â€”')."""
    if "â€" in text or "Ã" in text:
        try:
            return text.encode("cp1252").decode("utf-8")
        except UnicodeError:
            pass
    return text


def _table_to_df(result_set: dict) -> pd.DataFrame:
    cols = result_set["resultSetMetaData"]["rowType"]
    df = pd.DataFrame(result_set.get("data", []), columns=[c["name"] for c in cols])
    for c in cols:
        if c["type"].lower() in ("fixed", "real", "number", "float", "integer"):
            df[c["name"]] = pd.to_numeric(df[c["name"]], errors="coerce")
    return df


def parse_response(resp: dict) -> dict:
    """Turn an AGENT_RUN response into display blocks plus the plain-text answer."""
    if "content" not in resp:
        raise RuntimeError(resp.get("message") or json.dumps(resp)[:500])

    blocks, suggestions, text_parts = [], [], []
    for item in resp["content"]:
        kind = item.get("type")
        if kind == "text":
            text = _fix_mojibake(item["text"])
            text_parts.append(text)
            if blocks and blocks[-1]["type"] == "text":
                blocks[-1]["text"] += text
            else:
                blocks.append({"type": "text", "text": text})
        elif kind == "table":
            blocks.append({"type": "table", "title": item["table"].get("title", ""),
                           "df": _table_to_df(item["table"]["result_set"])})
        elif kind == "chart":
            blocks.append({"type": "chart", "spec": json.loads(item["chart"]["chart_spec"])})
        elif kind == "suggested_queries":
            suggestions = [q["query"] for q in item.get("suggested_queries", [])]

    if resp.get("status") not in (None, "completed") and not text_parts:
        raise RuntimeError(f"Cortex returned status '{resp.get('status')}' with no answer.")

    return {"blocks": blocks, "suggestions": suggestions,
            "text": "".join(text_parts).strip()}


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_answer(answer: dict):
    for block in answer["blocks"]:
        if block["type"] == "text":
            # Escape $ so Streamlit doesn't treat dollar amounts as LaTeX.
            st.markdown(block["text"].replace("$", "\\$"))
        elif block["type"] == "table":
            if block["title"]:
                st.caption(block["title"])
            st.dataframe(block["df"], use_container_width=True, hide_index=True)
        elif block["type"] == "chart":
            st.vega_lite_chart(block["spec"], use_container_width=True)


def queue_question(question: str):
    st.session_state.queued_prompt = question


def main():
    session = get_active_session()

    st.title("The Credit Union Oracle")
    st.caption("Brought to You by America's Credit Unions. Powered by Snowflake Cortex.")

    try:
        st.image(session.file.get_stream(IMAGE_PATH, decompress=False).read(), width=300)
    except Exception as e:
        st.error(f"Error loading image from stage: {e}")

    with st.sidebar:
        if st.button("New conversation", use_container_width=True):
            st.session_state.messages = []

    st.divider()

    if "messages" not in st.session_state:
        st.session_state.messages = []

    # Replay conversation
    for i, msg in enumerate(st.session_state.messages):
        with st.chat_message(msg["role"]):
            if msg["role"] == "user":
                st.markdown(msg["text"])
            else:
                render_answer(msg["answer"])
                is_latest = i == len(st.session_state.messages) - 1
                if is_latest and msg["answer"]["suggestions"]:
                    st.caption("You might also ask:")
                    for j, q in enumerate(msg["answer"]["suggestions"]):
                        st.button(q, key=f"suggest_{i}_{j}", on_click=queue_question, args=(q,))

    prompt = st.chat_input("Ask the CU Oracle about US credit unions...")
    prompt = prompt or st.session_state.pop("queued_prompt", None)
    if not prompt:
        return

    history = list(st.session_state.messages)
    st.session_state.messages.append({"role": "user", "text": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Consulting the Oracle..."):
            try:
                answer = parse_response(ask_oracle(session, history, prompt))
            except Exception as e:
                st.error(f"The Oracle could not answer: {e}")
                st.session_state.messages.pop()  # don't keep an unanswered question in history
                return
        st.session_state.messages.append({"role": "assistant", "text": answer["text"], "answer": answer})
    st.rerun()  # redraw so suggestion buttons appear under the new answer


if __name__ == "__main__":
    main()
