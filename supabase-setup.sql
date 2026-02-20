-- =============================================================
-- US Legal Advisor AI - Supabase Setup
-- Project: Chatbot_juridique (same project as Senegalese chatbot)
-- Table: us_legal_documents (separate from 'documents')
-- =============================================================

-- 1. Create the table for US legal documents
CREATE TABLE IF NOT EXISTS us_legal_documents (
  id BIGSERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  embedding VECTOR(1536)  -- text-embedding-3-small dimension
);

-- 2. Create vector similarity search index (IVFFlat)
CREATE INDEX IF NOT EXISTS us_legal_documents_embedding_idx
ON us_legal_documents
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 3. Create GIN index on metadata for fast JSONB filtering
CREATE INDEX IF NOT EXISTS us_legal_documents_metadata_idx
ON us_legal_documents
USING GIN (metadata);

-- 4. Enable Row Level Security
ALTER TABLE us_legal_documents ENABLE ROW LEVEL SECURITY;

-- 5. Public read access policy
CREATE POLICY "Public read access for us_legal_documents"
ON us_legal_documents
FOR SELECT
TO public, anon, authenticated
USING (true);

-- 6. Service role write access policy
CREATE POLICY "Service role write access for us_legal_documents"
ON us_legal_documents
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- 7. Vector search function (SAME signature as match_documents for LangChain/n8n compatibility)
-- DROP any existing versions first to avoid PGRST203 duplicate error
DROP FUNCTION IF EXISTS match_us_legal_documents(vector, jsonb, int);
DROP FUNCTION IF EXISTS match_us_legal_documents(vector(1536), jsonb, int);

CREATE OR REPLACE FUNCTION match_us_legal_documents (
  query_embedding VECTOR(1536),
  filter JSONB DEFAULT '{}'::jsonb,
  match_count INT DEFAULT 8
)
RETURNS TABLE (
  id BIGINT,
  content TEXT,
  metadata JSONB,
  similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    us_legal_documents.id,
    us_legal_documents.content,
    us_legal_documents.metadata,
    1 - (us_legal_documents.embedding <=> query_embedding) AS similarity
  FROM us_legal_documents
  WHERE
    CASE
      WHEN filter ? 'source' THEN us_legal_documents.metadata->>'source' = filter->>'source'
      ELSE TRUE
    END
  ORDER BY us_legal_documents.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- =============================================================
-- VERIFICATION: Run these queries to confirm setup
-- =============================================================
-- SELECT count(*) FROM us_legal_documents;  -- Should be 0
-- SELECT * FROM pg_proc WHERE proname = 'match_us_legal_documents';  -- Should return 1 row
-- \d us_legal_documents  -- Should show id, content, metadata, embedding columns

-- =============================================================
-- METADATA SCHEMA for indexation:
-- {
--   "source": "Title 18 USC - Crimes and Criminal Procedure",
--   "section": "§ 1001",
--   "title": "Statements or entries generally",
--   "chapter": "Chapter 47 - Fraud and False Statements",
--   "url": "https://www.law.cornell.edu/uscode/text/18/1001",
--   "chunk_index": 0,
--   "total_chunks": 3
-- }
-- =============================================================
