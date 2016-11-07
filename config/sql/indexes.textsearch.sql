CREATE INDEX wikipedia_index_textsearch ON wikipedia
 USING GIN (to_tsvector('english', title),
            to_tsvector('english', substring(text from 0 for 1000000)));
