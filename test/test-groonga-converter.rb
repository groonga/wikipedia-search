require "stringio"
require "wikipedia-search/groonga-converter"

class TestGroongaConverter < Test::Unit::TestCase
  def convert(xml, options={})
    input = StringIO.new(xml)
    output = StringIO.new
    converter = WikipediaSearch::GroongaConverter.new(input, options)
    converter.convert(output)
    output.string
  end

  def test_empty
    xml = <<-XML
<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.8/">
</mediawiki>
    XML
    assert_equal(<<-GROONGA, convert(xml))
load --table Pages
[
]
    GROONGA
  end

  def test_one
    xml = <<-XML
<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.8/">
  <page>
    <title>Title</title>
    <id>1</id>
    <revision>
      <id>1001</id>
      <text>Text1 &amp; Text2</text>
    </revision>
  </page>
</mediawiki>
    XML
    assert_equal(<<-GROONGA, convert(xml))
load --table Pages
[
{"_key":1,"title":"Title","text":"Text1 & Text2"}
]
    GROONGA
  end

  def test_max_n_records
    xml = <<-XML
<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.8/">
  <page>
    <title>Title1</title>
    <id>1</id>
    <revision>
      <id>1001</id>
      <text>Text1</text>
    </revision>
  </page>
  <page>
    <title>Title2</title>
    <id>2</id>
    <revision>
      <id>1002</id>
      <text>Text2</text>
    </revision>
  </page>
</mediawiki>
    XML
    assert_equal(<<-GROONGA, convert(xml, :max_n_records => 1))
load --table Pages
[
{"_key":1,"title":"Title1","text":"Text1"}
]
    GROONGA
  end
end
