require "csv"

require "wikipedia-search/converter"

module WikipediaSearch
  class CSVConverter < Converter
    private
    def create_listener(output)
      CSVListener.new(output, @options)
    end

    class CSVListener < Listener
      def on_start
        @csv = CSV.new(@output)
      end

      def on_finish
        @csv.close
      end

      def on_page(page)
        record_values = [
          @page.id,
          escape_string(@page.title),
          escape_string(shorten_text(@page.text)),
        ]
        @csv << record_values
      end

      private
      def escape_string(string)
        string.gsub(/[\\\r\n]/) do |special_character|
          case special_character
          when "\r"
            "\\r"
          when "\n"
            "\\n"
          else
            "\\#{special_character}"
          end
        end
      end
    end
  end
end
