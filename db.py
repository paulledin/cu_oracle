"""Snowflake connection for the CU Oracle app.

Config comes from ``[connections.snowflake]`` in Streamlit secrets:

    [connections.snowflake]
    account   = "CUNA-POLICYAZUREPROD"
    user      = "CU_ORACLE_APP_SVC"
    role      = "CU_ORACLE_APP_READ"
    warehouse = "STREAMLIT_WH"
    # RSA key-pair: paste the PEM as private_key, or point private_key_path at
    # a file for local runs.
    private_key = "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
    # private_key_passphrase = "..."   # only if the key is encrypted
    #
    # Local dev alternative: browser SSO -
    # authenticator = "externalbrowser"   (omit the private_key lines)

One cached connection serves every user; ``query_one`` reconnects and retries
once if the session has expired.
"""
from pathlib import Path

import snowflake.connector
import streamlit as st


def _load_private_key(pem_text, passphrase):
    """PEM (encrypted or not) -> DER PKCS8 bytes for snowflake.connector."""
    from cryptography.hazmat.primitives import serialization
    key = serialization.load_pem_private_key(
        pem_text.encode(),
        password=passphrase.encode() if passphrase else None,
    )
    return key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


@st.cache_resource(show_spinner="Connecting to Snowflake...")
def _connection():
    cfg = dict(st.secrets["connections"]["snowflake"])
    params = {k: cfg[k] for k in ("account", "user", "role", "warehouse",
                                  "database", "schema") if cfg.get(k)}
    if cfg.get("authenticator"):
        params["authenticator"] = cfg["authenticator"]

    pem = cfg.get("private_key")
    key_path = cfg.get("private_key_path")
    if pem or key_path:
        if not pem:
            pem = Path(key_path).read_text()
        params["private_key"] = _load_private_key(pem, cfg.get("private_key_passphrase"))
    elif cfg.get("password"):
        params["password"] = cfg["password"]

    # Heartbeat so the cached session's token doesn't lapse between visits.
    params["client_session_keep_alive"] = True
    return snowflake.connector.connect(**params)


# Snowflake errnos for a session/token that's no longer valid: expired token
# (390114), session gone (390112), session expired (390111).
_EXPIRED_ERRNOS = {390111, 390112, 390114}


def _is_expired(exc):
    return (getattr(exc, "errno", None) in _EXPIRED_ERRNOS
            or "token has expired" in str(exc).lower())


def query_one(sql, params=None):
    """Run a statement and return the first column of the first row."""
    try:
        cur = _connection().cursor()
        cur.execute(sql, params)
    except Exception as exc:
        if not _is_expired(exc):
            raise
        _connection.clear()  # drop the dead session, log in again
        cur = _connection().cursor()
        cur.execute(sql, params)
    try:
        return cur.fetchone()[0]
    finally:
        cur.close()
