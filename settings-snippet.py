# The database block for settings.py: SQLite by default, anything else if the
# environment says so. Paste this in place of the DATABASES dict that
# startproject generated.
#
#   uv add dj-database-url "psycopg[binary]"
#
# dj-database-url is already in the Part 11 dependency list, so this adds
# nothing new to the tutorial. (Part 11 lists psycopg2-binary; psycopg[binary]
# is the current driver and what Django 5+ prefers. Either works — just pick
# one and keep the class on it.)

import dj_database_url

DATABASES = {
    "default": dj_database_url.config(
        # No DATABASE_URL in the environment -> local SQLite, exactly as before.
        # This is the whole "works on my laptop, Postgres in production" story,
        # and it is one function call.
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
        # Reuse connections for 10 minutes instead of reconnecting per request.
        conn_max_age=600,
        # Check a pooled connection is still alive before handing it out —
        # without this, a Postgres restart gives every app a burst of
        # "server closed the connection unexpectedly" until the pool cycles.
        conn_health_checks=True,
    )
}

# Required behind Caddy (or any TLS-terminating proxy). Without it Django
# believes every request arrived over plain HTTP: CSRF failures on login that
# make no sense, and an infinite redirect loop if SECURE_SSL_REDIRECT is on.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
