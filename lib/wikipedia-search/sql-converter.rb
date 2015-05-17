require "wikipedia-search/converter"

module WikipediaSearch
  class SQLConverter < Converter
    private
    def create_listener(output)
      SQLListener.new(output, @options)
    end

    class SQLListener < Listener
      private
      def on_start
        @output.puts("INSERT INTO pages VALUES (id, title, text)")
      end

      def on_finish
        @output.puts unless first_page?
        @output.puts(";")
      end

      def on_page(page)
        @output.puts(",") unless first_page?
        record_values = [
          @page.id,
          escape_string(@page.title),
          escape_string(shorten_text(@page.text)),
        ]
        @output.print("(#{record_values.join(', ')})")
      end

      def escape_string(string)
        escaped_content = string.gsub(/["\\\n]/) do |special_character|
          case special_character
          when "\n"
            "\\n"
          else
            "\\#{special_character}"
          end
        end
        "\"#{escaped_content}\""
      end
    end
  end
end
