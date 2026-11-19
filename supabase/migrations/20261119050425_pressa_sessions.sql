CREATE TABLE IF NOT EXISTS public.app_sessions (
    session_id varchar(128) PRIMARY KEY,
    session_data text NOT NULL,
    expires_at bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS app_sessions_expires_at_idx ON public.app_sessions (expires_at);
ALTER TABLE public.app_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.app_sessions FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_sessions TO service_role;
