CREATE INDEX wikipedia_index_textsearch ON wikipedia
 USING GIN (to_tsvector('english', title), to_tsvector('english', text));
