require "json"

require_relative "converter"

module WikipediaSearch
  class GroongaConverter < Converter
    private
    def convert_start
      @output.puts("load --table Pages")
      @output.puts("[")
    end

    def convert_finish
      @output.puts unless @first_page
      @output.puts("]")
    end

    def convert_page(page)
      @output.puts(",") unless @first_page
      record = {
        "_key"  => page.id,
        "title" => page.title,
        "text"  => shorten_text(page.revision.text),
        "categories" => extract_categories(page.revision.text),
      }
      @output.print(JSON.generate(record))
    end
  end
end
