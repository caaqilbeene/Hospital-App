-- ====================================================================
-- SUPABASE CHAT ARCHITECTURE & SECURITY MIGRATION SCRIPT (FIXED)
-- Hospital Booking App - Multi-Doctor Isolated Conversations & Presence
-- ====================================================================

-- 1. EXTEND DOCTORS TABLE
ALTER TABLE doctors 
ADD COLUMN IF NOT EXISTS user_id TEXT,
ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ DEFAULT now();

-- 2. EXTEND PATIENTS TABLE
ALTER TABLE patients 
ADD COLUMN IF NOT EXISTS user_id TEXT;

-- 3. EXTEND MESSAGES TABLE FIRST (Ensure doctor_id & conversation_id exist)
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS doctor_id TEXT,
ADD COLUMN IF NOT EXISTS doctor_name TEXT,
ADD COLUMN IF NOT EXISTS conversation_id TEXT;

-- 4. CREATE CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    patient_id TEXT NOT NULL,
    doctor_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT unique_patient_doctor_pair UNIQUE (patient_id, doctor_id)
);

-- Index for instant lookup of conversations
CREATE INDEX IF NOT EXISTS idx_conversations_patient_doctor ON conversations(patient_id, doctor_id);
CREATE INDEX IF NOT EXISTS idx_conversations_doctor ON conversations(doctor_id);
CREATE INDEX IF NOT EXISTS idx_conversations_patient ON conversations(patient_id);

-- Index for conversation messages retrieval
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);

-- 5. SAFELY MIGRATE HISTORICAL DATA
INSERT INTO conversations (patient_id, doctor_id, created_at, updated_at)
SELECT DISTINCT 
    COALESCE(NULLIF(patient_id, ''), 'usr_1') AS patient_id,
    COALESCE(NULLIF(doctor_id, ''), 'doc_1') AS doctor_id,
    NOW(),
    NOW()
FROM messages
WHERE (patient_id IS NOT NULL AND patient_id != '')
ON CONFLICT (patient_id, doctor_id) DO NOTHING;

-- Also insert default conversation for Dr. Mukhtar (doc_1) & Patient Williams (usr_1) if not exists
INSERT INTO conversations (patient_id, doctor_id)
VALUES ('usr_1', 'doc_1')
ON CONFLICT (patient_id, doctor_id) DO NOTHING;

-- Populate conversation_id in messages table for matching records
UPDATE messages m
SET conversation_id = c.id
FROM conversations c
WHERE (m.conversation_id IS NULL OR m.conversation_id = '')
  AND (
      (m.patient_id = c.patient_id AND m.doctor_id = c.doctor_id)
   OR (m.patient_id = c.patient_id AND (m.doctor_id IS NULL OR m.doctor_id = '') AND c.doctor_id = 'doc_1')
  );

-- For any remaining messages without conversation_id, link them to the default Dr. Mukhtar conversation
UPDATE messages
SET conversation_id = (SELECT id FROM conversations WHERE patient_id = 'usr_1' AND doctor_id = 'doc_1' LIMIT 1)
WHERE conversation_id IS NULL OR conversation_id = '';

-- 6. ENABLE ROW LEVEL SECURITY (RLS)
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any to avoid duplicates
DROP POLICY IF EXISTS "Allow patients and doctors access to conversations" ON conversations;
DROP POLICY IF EXISTS "Allow patients and doctors access to messages" ON messages;

-- Create policies for conversations & messages
CREATE POLICY "Allow patients and doctors access to conversations" ON conversations
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Allow patients and doctors access to messages" ON messages
    FOR ALL USING (true) WITH CHECK (true);
