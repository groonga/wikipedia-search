require "json"
require "rexml/streamlistener"
require "rexml/parsers/baseparser"
require "rexml/parsers/streamparser"

module WikipediaSearch
  class GroongaConverter
    def initialize(input)
      @input = input
    end

    def convert(output)
      listener = Listener.new(output)
      parser = REXML::Parsers::StreamParser.new(@input, listener)
      parser.parse
      listener.finish
    end

    class Listener
      include REXML::StreamListener

      def initialize(output)
        @output = output
        @text_stack = [""]
        @first_page = true
        @output.puts("load --table Pages")
        @output.puts("[")
      end

      def finish
        @output.puts unless @first_page
        @output.puts("]")
      end

      def tag_start(name, attributes)
        push_stacks
        case name
        when "page"
          @title = nil
          @id = nil
          @text = nil
        end
      end

      def tag_end(name)
        case name
        when "page"
          if @first_page
            @first_page = false
          else
            @output.puts(",")
          end
          page = {
            "_key"  => @id,
            "title" => @title,
            "text"  => @text,
          }
          @output.print(JSON.generate(page))
        when "title"
          @title = @text_stack.last
        when "id"
          @id ||= Integer(@text_stack.last)
        when "text"
          @text = @text_stack.last
        end
        pop_stacks
      end

      def text(data)
        @text_stack.last << data
      end

      def cdata(contnet)
        @text_stack.last << content
      end

      private
      def push_stacks
        @text_stack << ""
      end

      def pop_stacks
        @text_stack.pop
      end
    end
  end
end
