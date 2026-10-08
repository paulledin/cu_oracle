"""Passphrase login gate.

Every signed-in user gets the same Oracle. Groups exist as separate entries so
different audiences can have their own passphrase (and one can be revoked or
rotated without affecting the others), defined in .streamlit/secrets.toml
(never committed):

    [groups.acu_staff]
    label = "America's Credit Unions staff"
    password = "..."

Every group's password must be unique - the password is what tells the app
which group a user belongs to.
"""

import hmac
import logging

import streamlit as st

log = logging.getLogger("cu_oracle")
CONTACT = "custat@americascreditunions.org"


def _groups():
    return {key: dict(cfg) for key, cfg in st.secrets.get("groups", {}).items()}


def match_group(passphrase):
    """Return (group_key, group_cfg) for a passphrase, or (None, None)."""
    found = None
    # Check every group (no early exit) so timing doesn't reveal which matched.
    for key, cfg in _groups().items():
        if hmac.compare_digest(passphrase.encode(), str(cfg.get("password", "")).encode()):
            found = (key, cfg)
    return found or (None, None)


def current_group():
    """The logged-in group's config dict (with its key under 'key'), or None."""
    return st.session_state.get("group")


def login_sidebar():
    """Render the sidebar login / logout. Returns the group dict or None."""
    group = current_group()
    if group:
        st.sidebar.info(f"Signed in: **{group['label']}**", icon=":material/check_circle:")  # info = brand Blue (theme blueColor)
        if st.sidebar.button("Sign out", width="stretch"):
            del st.session_state["group"]
            st.session_state.messages = []
            st.rerun()
        return group

    with st.sidebar.form("login", clear_on_submit=True):
        passphrase = st.text_input("Please enter the passphrase:", type="password")
        submitted = st.form_submit_button("Sign in", width="stretch")

    if submitted and passphrase:
        key, cfg = match_group(passphrase)
        if key:
            st.session_state["group"] = {"key": key, "label": cfg.get("label", key)}
            log.info("login ok: group=%s", key)
            st.rerun()
        log.info("login failed")
        st.sidebar.error("Passphrase not correct.")
        st.sidebar.markdown(f"Please try again or contact {CONTACT} for assistance.")
    return None
