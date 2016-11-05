CREATE INDEX wikipedia_index_pg_bigm ON wikipedia
 USING GIN (title gin_bigm_ops, text gin_bigm_ops);
