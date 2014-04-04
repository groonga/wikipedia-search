require "stringio"
require "wikipedia-search/groonga-converter"

class TestGroongaConverter < Test::Unit::TestCase
  def convert(xml)
    input = StringIO.new(xml)
    output = StringIO.new
    converter = WikipediaSearch::GroongaConverter.new(input)
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
end
