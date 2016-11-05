CREATE INDEX wikipedia_index_pg_trgm ON wikipedia
 USING GIN (title gin_trgm_ops, text gin_trgm_ops);
