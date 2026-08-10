-- ============================================================
-- Users & Watchlists
-- ============================================================

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One watchlist per user, enforced via UNIQUE on user_id.
CREATE TABLE watchlists (
    watchlist_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE watchlist_tickers (
    watchlist_id INTEGER NOT NULL REFERENCES watchlists(watchlist_id),
    symbol TEXT NOT NULL,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (watchlist_id, symbol)
);

-- ============================================================
-- Market data
-- ============================================================

CREATE TABLE companies (
    symbol TEXT PRIMARY KEY,
    name TEXT,
    sector TEXT,
    industry TEXT,
    description TEXT,          -- company profile text, embedded for semantic retrieval
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Composite PK: one row per symbol per timestamp, since this is time-series data.
CREATE TABLE price_snapshots (
    symbol TEXT NOT NULL REFERENCES companies(symbol),
    snapshot_time TIMESTAMPTZ NOT NULL,
    price NUMERIC NOT NULL,
    volume BIGINT,
    source TEXT NOT NULL DEFAULT 'massive',
    daily_return_pct NUMERIC,
    moving_avg_7d NUMERIC,
    PRIMARY KEY (symbol, snapshot_time)
);

CREATE INDEX IF NOT EXISTS idx_price_snapshots_symbol_time
    ON price_snapshots (symbol, snapshot_time DESC);

-- ============================================================
-- Unstructured text sources (embedded for RAG)
-- ============================================================

CREATE TABLE news_articles (
    id TEXT PRIMARY KEY,           -- external article id from Massive
    symbol TEXT REFERENCES companies(symbol),
    title TEXT NOT NULL,
    description TEXT,              -- narrative text to embed
    source TEXT,
    published_at TIMESTAMPTZ,
    url TEXT,
    payload JSONB NOT NULL,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_news_articles_symbol ON news_articles (symbol);

-- Filings excerpts and earnings-call summaries. Kept separate from
-- news_articles since they come from different sources and have a
-- different natural shape (long-form document text, not a short article).
CREATE TABLE company_documents (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL REFERENCES companies(symbol),
    document_type TEXT NOT NULL,   -- 'filing_excerpt' or 'earnings_summary'
    title TEXT,
    document_text TEXT NOT NULL,   -- long-form narrative text, embedded for RAG
    source_url TEXT,
    published_at TIMESTAMPTZ,
    payload JSONB,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_company_documents_symbol
    ON company_documents (symbol);

CREATE INDEX IF NOT EXISTS idx_company_documents_type
    ON company_documents (document_type);

-- ============================================================
-- User-generated content (agent write actions land here)
-- ============================================================

CREATE TABLE research_notes (
    note_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    symbol TEXT REFERENCES companies(symbol),
    note_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analysis_reports (
    report_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    symbols TEXT[] NOT NULL,       -- array, since a report may compare multiple tickers
    report_type TEXT NOT NULL DEFAULT 'summary',  -- e.g. 'summary', 'comparison', 'thesis_check'
    report_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- Embeddings (not one of the 8 named tables, but required by
-- the "context engineering" section - mirrors weather_embeddings
-- from the Day 2 homework)
-- ============================================================

CREATE TABLE document_embeddings (
    id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,     -- 'company_profile', 'news_article', 'filing_excerpt', 'earnings_summary'
    source_id TEXT NOT NULL,       -- e.g. companies.symbol or news_articles.id
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    embedding VECTOR(384),
    model_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_document_embeddings_source
    ON document_embeddings (source_type, source_id);

CREATE INDEX IF NOT EXISTS idx_document_embeddings_hnsw
    ON document_embeddings USING hnsw (embedding vector_cosine_ops);
