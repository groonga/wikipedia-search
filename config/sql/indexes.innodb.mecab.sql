ALTER TABLE wikipedia ADD FULLTEXT INDEX fulltext_index (title, text)
  WITH PARSER MeCab;
