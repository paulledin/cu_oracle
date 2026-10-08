# The Credit Union Oracle

A Streamlit chat app that answers questions about US credit unions using only
the data in the `CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_SEMANTIC` semantic view.

Each question is sent to a Snowflake Cortex Agent (`SNOWFLAKE.CORTEX.AGENT_RUN`)
whose only tool is Cortex Analyst over that semantic view. Cortex plans the
lookup, runs it, and writes the answer; the app renders the returned text,
tables, charts, and suggested follow-up questions. The app itself never writes
SQL. To improve answers, edit the semantic view (descriptions, verified
queries, `ai_sql_generation` / `ai_question_categorization`) or the
instruction constants at the top of `CU_Oracle.py`.

## Files

| File | Purpose |
|---|---|
| `CU_Oracle.py` | App: login gate, chat UI, Cortex Agent request/response handling |
| `db.py` | Snowflake connection (key-pair service account, keep-alive, reconnect) |
| `auth.py` | Passphrase groups from Streamlit secrets |
| `assets/Socrates.png` | Header image |
| `.streamlit/secrets.toml.example` | Secrets template (groups + Snowflake connection) |
| `snowflake/cu_oracle_semantic.sql` | Semantic view definition (source of truth; run as SYSADMIN) |
| `snowflake/ncua_financials_history.sql` | Procedure + daily task that rebuild the five-year quarterly NCUA history table |

## Data

The semantic view covers three tables in `CU_ORACLE_AGENT_DB.ANALYTICS`:

- `CU_ORACLE_LIVE` - credit union names, contacts, status, leagues (NIMBLE).
- `NCUA_FINANCIALS_HISTORY` - NCUA call report financials, one row per credit
  union per quarter for the latest 21 quarters (five years plus the matching
  quarter five years back). Includes year-to-date, quarterly, and annualized
  income and charge-offs, ratios (`_PCT`), and year-over-year growth. Rebuilt by
  `REFRESH_NCUA_FINANCIALS_HISTORY`, which a daily 6am ET task runs; it only
  rebuilds when a newer `NCUA_DATA.FINANCIALS.NCUA_FINANCIALS_YYYYMM` table exists.
- `CURRENT_NCUA_BRANCH_FILE` - NCUA branch locations.

Schema future grants give `CU_ORACLE_APP_READ` access to anything (re)created in
`ANALYTICS`, so rebuilds don't break the app.

## Deployment (Streamlit Community Cloud)

- Main file: `CU_Oracle.py`. Pushing to `main` redeploys.
- Secrets: paste the filled-in `secrets.toml.example` into App settings -> Secrets.
- Snowflake: service account `CU_ORACLE_APP_SVC`, role `CU_ORACLE_APP_READ`
  (USAGE on `STREAMLIT_WH`, `SNOWFLAKE.CORTEX_USER`, SELECT on the semantic
  view and its three tables).

## Local run

    python -m streamlit run CU_Oracle.py

with `.streamlit/secrets.toml` filled in (service key or `externalbrowser`).

## Cost note

`ORCHESTRATION_MODEL = "auto"` currently resolves to a Claude Opus model and
uses roughly 135K-200K input tokens per question (mostly cache reads). Pin a
cheaper model there if needed.
