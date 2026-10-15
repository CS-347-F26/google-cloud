# The database and environment block for settings.py.
#
# Add production dependencies to a dependency group:
#
#   uv add --group prod "psycopg[binary]" gunicorn
#
# WhiteNoise is a regular dependency, not prod-only: settings.py names its
# middleware, so it has to import on a laptop too.
#
#   uv add whitenoise
#
# Then in settings.py, replace the DATABASES dict startproject generated
# with the block below.

import environ

env = environ.Env()

DATABASES = {
    "default": env.db(default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}")
}

ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["localhost", "127.0.0.1"])
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# Required behind Caddy (or any TLS-terminating proxy). Without it Django
# believes every request arrived over plain HTTP: CSRF failures on login that
# make no sense, and an infinite redirect loop if SECURE_SSL_REDIRECT is on.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# The Dockerfile runs collectstatic, which needs somewhere to collect to.
# BASE_DIR / "staticfiles" is inside /app in the image; add staticfiles/ to
# .gitignore if you ever run collectstatic locally.
STATIC_ROOT = BASE_DIR / "staticfiles"

# With DEBUG=False, Django stops serving /static/ and Caddy only proxies, so
# without this every page loads with no CSS. Add it to MIDDLEWARE directly
# after SecurityMiddleware:
#
#   MIDDLEWARE = [
#       "django.middleware.security.SecurityMiddleware",
#       "whitenoise.middleware.WhiteNoiseMiddleware",
#       ...
#   ]
