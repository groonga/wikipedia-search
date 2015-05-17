require "json"

require "wikipedia-search/converter"

module WikipediaSearch
  class GroongaConverter < Converter
    private
    def create_listener(output)
      GroongaListener.new(output, @options)
    end

    class GroongaListener < Listener
      private
      def on_start
        @output.puts("load --table Pages")
        @output.puts("[")
      end

      def on_finish
        @output.puts unless first_page?
        @output.puts("]")
      end

      def on_page(page)
        @output.puts(",") unless first_page?
        page = {
          "_key"  => @page.id,
          "title" => @page.title,
          "text"  => shorten_text(@page.text),
          "categories" => @page.extract_categories,
        }
        @output.print(JSON.generate(page))
      end
    end
  end
end
