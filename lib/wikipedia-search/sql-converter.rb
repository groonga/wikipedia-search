require "wikipedia-search/converter"

module WikipediaSearch
  class SQLConverter < Converter
    private
    def create_listener(output)
      SQLOneShotListener.new(output, @options)
      # SQLBulkListener.new(output, @options)
    end

    class SQLListener < Listener
      private
      def escape_string(string)
        escaped_content = string.gsub(/['\\\n]/) do |special_character|
          case special_character
          when "\n"
            "\\n"
          when "'"
            "''"
          else
            "\\#{special_character}"
          end
        end
        "'#{escaped_content}'"
      end
    end

    class SQLOneShotListener < SQLListener
      private
      def on_start
      end

      def on_finish
      end

      def on_page(page)
        record_values = [
          @page.id,
          escape_string(@page.title),
          escape_string(shorten_text(@page.text)),
        ]
        @output.print("INSERT INTO wikipedia (id, title, text) VALUES ")
        @output.print("(#{record_values.join(', ')});")
      end
    end

    class SQLBulkListener < SQLListener
      private
      def on_start
        @output.puts("INSERT INTO wikipedia (id, title, text) VALUES")
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
    end
  end
end
