CREATE INDEX wikipedia_index_pgroonga ON wikipedia
 USING pgroonga (title, text);
