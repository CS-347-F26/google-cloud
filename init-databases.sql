-- One database per app, all owned by the single POSTGRES_USER.
--
-- IMPORTANT: Postgres runs this file only when its data directory is empty —
-- that is, on the very first `docker compose up`. Adding a fourth app later
-- will NOT re-run it. Create that database by hand instead:
--
--     docker compose exec postgres createdb -U "$POSTGRES_USER" app4
--
-- (Editing this file after the fact does nothing, which is a confusing way to
-- lose an afternoon.)

CREATE DATABASE locallibrary;
CREATE DATABASE chat;
CREATE DATABASE app3;
