# Supabase copy for Pressa

Source: `C:/Users/AlanE/Downloads/pressa.sql` (MariaDB 10.11, demo database `pressa`). Target: Supabase project `Pressa`, ref `bkylsgaxfjfeethwgkls`.

The snapshot contains 31 base tables, 26 data-bearing tables, 6 views, and demo records. The converted schema also includes all 49 foreign keys, 117 indexes, 27 business triggers, 3 timestamp triggers, and PostgreSQL versions of the 3 stored procedures. `file_synchro.contenu` is converted to `jsonb`. Row Level Security is enabled on every table. The `anon` and `authenticated` roles have no direct table/sequence/function privileges; the service role retains server-side access.

The converted SQL is kept in `migrations/` in execution order. `scripts/convert_pressa_dump.py` recreates it from the supplied dump. Running the files against a fresh project provisions the schema, imports the included demonstration snapshot, then creates views, triggers, procedures, access grants, and the e-mail channel.

The live project was provisioned through the Supabase SQL connector, so Supabase's migration-history table was not updated by these direct SQL calls. Keep the local SQL files as the authoritative migration record. Do not re-run the create-table or seed scripts on the already populated project.

The PHP app now accepts `PRESSA_DB_DRIVER=pgsql` and `PRESSA_DATABASE_URL`; its local default remains MySQL. The live Vercel app still needs the existing database connection URL/password added to its environment. This work did not reset or change any password.
