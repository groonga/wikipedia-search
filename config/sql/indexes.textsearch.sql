CREATE INDEX wikipedia_index_textsearch ON wikipedia
 USING gin (to_tsvector('english', title), to_tsvector('english', text));
