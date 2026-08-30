-- ============================================================================
-- NASIIB HOSPITAL: EMAIL LOGS & BROADCAST EMAILS TABLE MIGRATION
-- ============================================================================

-- 1. Create `broadcast_emails` table
CREATE TABLE IF NOT EXISTS public.broadcast_emails (
    id TEXT PRIMARY KEY,
    recipient_email TEXT NOT NULL,
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    sender TEXT DEFAULT 'Nasiib Hospital Admin',
    status TEXT DEFAULT 'sent',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2. Create index on recipient_email and created_at
CREATE INDEX IF NOT EXISTS idx_broadcast_emails_recipient ON public.broadcast_emails(recipient_email);
CREATE INDEX IF NOT EXISTS idx_broadcast_emails_created_at ON public.broadcast_emails(created_at DESC);

-- 3. Also create generic `emails` table alias for compatibility
CREATE TABLE IF NOT EXISTS public.emails (
    id BIGSERIAL PRIMARY KEY,
    recipient_email TEXT NOT NULL,
    subject TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT DEFAULT 'sent',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_emails_recipient ON public.emails(recipient_email);

-- 4. Enable Row Level Security (RLS) with full open access for app operations
ALTER TABLE public.broadcast_emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emails ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on broadcast_emails"
ON public.broadcast_emails FOR ALL
TO public, anon, authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Allow all operations on emails"
ON public.emails FOR ALL
TO public, anon, authenticated
USING (true)
WITH CHECK (true);
