# Modified version of ERB specifically used to help convert ERB templates to Haml
class ERB
  class HamlCompiler < Compiler # :nodoc:
    class Buffer # :nodoc:
      def initialize(compiler, delimiter)
        @compiler = compiler
        @line = []
        @script = ""
        @delimiter = delimiter
        @compiler.pre_cmd.each do |x|
          push(x)
        end
      end
      attr_reader :script

      def push(cmd)
        @line << cmd
      end
      
      def cr
        @script << (@line.join(@delimiter))
        @line = []
        @script << @delimiter
      end
      
      def close
        return unless @line
        @compiler.post_cmd.each do |x|
          push(x)
        end
        @script << (@line.join(@delimiter))
        @line = nil
      end
    end

    def compile(s, delimiter = '; ')
      out = Buffer.new(self, delimiter)

      content = ''
      scanner = make_scanner(s)
      scanner.scan do |token|
        if scanner.stag.nil?
          case token
          when PercentLine
            out.push("#{@put_cmd} #{content.dump}") if content.size > 0
            content = ''
            out.push(token.to_s)
            out.cr
          when :cr
            out.cr
          when '<%', '<%=', '<%#'
            scanner.stag = token
            out.push("#{@put_cmd} #{content.dump}") if content.size > 0
            content = ''
          when "\n"
            content << "\n"
            out.push("#{@put_cmd} #{content.dump}")
            out.cr
            content = ''
          when '<%%'
            content << '<%'
          else
            content << token
          end
        else
          case token
          when '%>'
            case scanner.stag
            when '<%'
              if content[-1] == ?\n
                content.chop!
                out.push(content)
                out.cr
              else
                out.push(content)
              end
            when '<%='
              out.push("#{@insert_cmd}((#{content}).to_s)")
            when '<%#'
              # out.push("# #{content.dump}")
            end
            scanner.stag = nil
            content = ''
          when '%%>'
            content << '%>'
          else
            content << token
          end
        end
      end
      out.push("#{@put_cmd} #{content.dump}") if content.size > 0
      out.close
      out.script
    end
  end
end
