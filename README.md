# CS-347 — 3-5 Django apps per student on Compute Engine, each on its own subdomain

**One project per student, one VM, one Docker Compose file, one subdomain per app, HTTPS everywhere,
Postgres in production and SQLite on the laptop.** Adding an app is six lines of compose, three of
Caddyfile, one of `.env`, one `CREATE DATABASE`. Rebuilding a wrecked VM is one command.

```
create-vm.sh         run once, from Cloud Shell
startup-script.sh    runs itself on the VM at every boot (swap + Docker)
docker-compose.yml   lives at /srv/apps — one stanza per app
Caddyfile            one block per app; identical for every student
init-databases.sql   one database per app
env.example          copy to /srv/apps/.env — the only per-student file
Dockerfile.example   copy into each app repo
settings-snippet.py  the DATABASES block + the proxy header
```

Result: `https://library.yourdomain.dev`, `https://chat.yourdomain.dev`, … real certificates, no ports in
the URL, nothing to renew.

---

## Postgres lives in Compose, not Cloud SQL

You want Postgres deployed and SQLite locally. Both are handled, and the production half deliberately
does **not** use Cloud SQL.

With 30 independent student projects, Cloud SQL is ~$9-10/month *each* — roughly **$300/month, about
$950 for the semester**, to run a teaching database holding a few dozen rows. The Postgres in
`docker-compose.yml` is the same Postgres, on a box you're already paying for, at no extra cost. What
you give up is managed backups and failover, neither of which a course needs, and one of which is a
`pg_dump` one-liner anyway (below).

One Postgres container serves **one database per app**, which keeps the `DATABASE_URL`-per-app shape
students would meet at a real job.

### The SQLite-locally half

`settings-snippet.py` is the whole change:

```python
import environ
env = environ.Env()

DATABASES = {
    "default": env.db(default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}")
}
```

No `DATABASE_URL` in the environment means SQLite, so a laptop needs no configuration at all and a fresh
clone just runs. Compose sets `DATABASE_URL` per service, so the deployed copy is Postgres. `.env`
deliberately does **not** define `DATABASE_URL` — that absence is what makes the fallback work.

`django-environ` is a regular dependency (students use it locally too). `psycopg[binary]` and `gunicorn`
live in a `prod` dependency group in `pyproject.toml`, so `uv sync` on a laptop never installs them. The Dockerfile runs
`uv sync --locked --no-dev --group prod` to pull them in at build time.

## Sizing: 30 students, and where e2-micro runs out

Rough estimate, not a measurement — worth checking against one real VM before you commit the class:

| | e2-micro (1 GB, free tier) |
|---|---|
| Debian + Docker | ~120 MB |
| Caddy | ~20 MB |
| Postgres (`shared_buffers=64MB`) | ~110 MB |
| Redis | ~10 MB |
| Each Django app (1 worker, 4 threads) | ~120 MB |

Three apps lands near 650 MB and is comfortable. **Five apps lands around 900 MB and is not** — it will
run, on swap, badly. So: e2-micro is fine for the common case, and students who genuinely want five apps
should move to `e2-small` (2 GB). Cost per student per month, including the IP charge below:

- **e2-micro: ~$3.65** → about $110/month for 30 students, ~$385 for a semester.
- **e2-small: ~$16.90** → about $505/month, ~$1,775 for a semester.

Starting everyone on e2-micro and resizing the few who need it is a one-command change
(`gcloud compute instances set-machine-type`) and keeps the class bill inside teaching credits.

## DNS: one record, once

```
*.yourdomain.dev    A    <the static IP create-vm.sh printed>
```

One record covers every app they will ever add. Verify with `dig +short library.yourdomain.dev`
**before** starting Caddy — it requests a certificate on first request to a hostname, and that fails if
DNS isn't live yet.

## The four things that make this repeatable

1. **`--metadata-from-file=startup-script=…`** — the VM configures itself on boot, so a broken machine
   isn't something you debug over email, it's something you delete and recreate. It's also the one thing
   a screenshot can never be.
2. **A reserved static IP, created before the VM.** It's what the DNS record points at; an ephemeral IP
   changes on every stop/start and would silently break every hostname.
3. **OS Login + `gcloud compute ssh`.** Keys generated, uploaded and rotated for you. Delete steps 5 and
   6 of the old `google-cloud/README.md` — the manual `os-login ssh-keys add` and `add-metadata` calls
   are both unnecessary once `enable-oslogin=TRUE` is set at create time.
4. **`.env` is the only per-student file.** Everything else is byte-identical across the class, which is
   what makes "diff yours against the reference" a usable debugging instruction for 30 people.

## Student workflow

```bash
gcloud config set project <their-own-project>
./create-vm.sh <id>                       # prints the static IP
# ... add the wildcard A record, wait for DNS ...

gcloud compute ssh cs347-<id> --zone us-central1-c
cd /srv/apps
git clone <app-1> locallibrary
git clone <app-2> chat
cp env.example .env && nano .env
docker compose up -d --build

# every change after that
git -C locallibrary pull && docker compose up -d --build locallibrary
```

Migrations run on container start, so there is no separate deploy step.

## Backups

```bash
docker compose exec postgres pg_dumpall -U cs347 > ~/backup-$(date +%F).sql
```

Worth assigning once as a habit. The `pg_data` volume survives `docker compose down`, reboots, and
`up --build` — it does **not** survive `docker compose down -v`.

## The gotchas worth pre-empting

- **`SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")`** in every app. Caddy terminates TLS
  and forwards plain HTTP, so without it Django thinks every request is insecure: nonsensical CSRF
  failures on login, and an infinite redirect loop if `SECURE_SSL_REDIRECT` is on. This will be the
  single most common support request.
- **`docker compose down -v` now destroys their database**, not just certificates. Before, that flag
  cost a cert re-issue; now it costs the semester's data. Say it out loud in class.
- **`init-databases.sql` runs only once**, when Postgres first initialises an empty data directory.
  Adding a fourth app later means creating its database by hand:
  `docker compose exec postgres createdb -U cs347 app4`. Editing the SQL file after the fact does
  nothing, which is a confusing way to lose an afternoon.
- **Port 80 must stay open**, not just 443 — Let's Encrypt's HTTP-01 challenge uses it, and the symptom
  of closing it is a TLS error that points nowhere near DNS.
- **e2-micro is 1 GB** and `docker compose build` gets OOM-killed with nothing in the log but `Killed`.
  The startup script creates a 2 GB swapfile; don't remove it.
- **`.dev` is HSTS-preloaded**, so browsers refuse plain HTTP entirely. Fine once Caddy works, confusing
  while debugging — students can't fall back to `http://` to test.

## Cost and teardown

The `e2-micro` is always-free in us-central1/us-east1/us-west1, but since February 2024 every external
IPv4 attached to a running VM bills at $0.005/hour — about **$3.65/month**, ephemeral or static,
free-tier or not. That's the real floor. An *unattached* reserved address bills at a higher rate.

With one project per student, the cleanest teardown is `gcloud projects delete` — it takes the instance,
the disk and the address together, and leaves nothing to leak.
