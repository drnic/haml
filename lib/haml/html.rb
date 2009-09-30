require File.dirname(__FILE__) + '/../haml'

require 'haml/engine'
require 'rubygems'
require 'cgi'
require 'haml/herb'

module Haml
  class HTML
    # A module containing utility methods that every Hpricot node
    # should have.
    module Node
      # Returns the Haml representation of the given node.
      #
      # @param tabs [Fixnum] The indentation level of the resulting Haml.
      # @option options (see Haml::HTML#initialize)
      def to_haml(tabs, options)
        parse_text(self.to_s, tabs)
      end

      private

      def tabulate(tabs)
        '  ' * tabs
      end

      def parse_text(text, tabs)
        text.strip!
        if text.empty?
          String.new
        else
          lines = text.split("\n")

          lines.map do |line|
            line.strip!
            "#{tabulate(tabs)}#{'\\' if Haml::Engine::SPECIAL_CHARACTERS.include?(line[0])}#{line}\n"
          end.join
        end
      end
    end
  end
end

# Haml monkeypatches various Hpricot classes
# to add methods for conversion to Haml.
module Hpricot
  # @see Hpricot
  module Node
    include Haml::HTML::Node
  end

  # @see Hpricot
  class BaseEle
    include Haml::HTML::Node
  end
end

require 'hpricot'

module Haml
  # Converts HTML documents into Haml templates.
  # Depends on [Hpricot](http://code.whytheluckystiff.net/hpricot/) and
  # [ParseTree](http://parsetree.rubyforge.org/) for HTML parsing
  #
  # Example usage:
  #
  #     Haml::Engine.new("<a href='http://google.com'>Blat</a>").render
  #       #=> "%a{:href => 'http://google.com'} Blat"
  class HTML
    # @param template [String, Hpricot::Node] The HTML template to convert
    # @option options :rhtml [Boolean] (false) Whether or not to parse
    #   ERB's `<%= %>` and `<% %>` into Haml's `=` and `-`
    # @option options :xhtml [Boolean] (false) Whether or not to parse
    #   the HTML strictly as XHTML
    def initialize(template, options = {})
      
      @options = options

      if template.is_a? Hpricot::Node
        @template = template
      else
        if template.is_a? IO
          template = template.read
        end

        Haml::Util.check_encoding(template) {|msg, line| raise Haml::Error.new(msg, line)}

        if @options[:rhtml]
          template = convert_to_hamlified_markup(template)
        end

        method = @options[:xhtml] ? Hpricot.method(:XML) : method(:Hpricot)
        @template = method.call(template.gsub('&', '&amp;'))
      end
    end

    # Processes the document and returns the result as a string
    # containing the Haml template.
    def render
      @template.to_haml(0, @options)
    end
    alias_method :to_haml, :render

    TEXT_REGEXP = /^(\s*).*$/

    # @see Hpricot
    class ::Hpricot::Doc
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        (children || []).inject('') {|s, c| s << c.to_haml(0, options)}
      end
    end

    # @see Hpricot
    class ::Hpricot::XMLDecl
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        "#{tabulate(tabs)}!!! XML\n"
      end
    end

    # @see Hpricot
    class ::Hpricot::CData
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        "#{tabulate(tabs)}:cdata\n#{parse_text(self.content, tabs + 1)}"
      end
    end

    # @see Hpricot
    class ::Hpricot::DocType
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        attrs = public_id.scan(/DTD\s+([^\s]+)\s*([^\s]*)\s*([^\s]*)\s*\/\//)[0]
        raise Haml::SyntaxError.new("Invalid doctype") if attrs == nil

        type, version, strictness = attrs.map { |a| a.downcase }
        if type == "html"
          version = "1.0"
          strictness = "transitional"
        end

        if version == "1.0" || version.empty?
          version = nil
        end

        if strictness == 'transitional' || strictness.empty?
          strictness = nil
        end

        version = " #{version}" if version
        if strictness
          strictness[0] = strictness[0] - 32
          strictness = " #{strictness}"
        end

        "#{tabulate(tabs)}!!!#{version}#{strictness}\n"
      end
    end

    # @see Hpricot
    class ::Hpricot::Comment
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        "#{tabulate(tabs)}/\n#{parse_text(self.content, tabs + 1)}"
      end
    end

    # @see Hpricot
    class ::Hpricot::Elem
      # @see Haml::HTML::Node#to_haml
      def to_haml(tabs, options)
        output = tab_prefix = "#{tabulate(tabs)}"
        if options[:rhtml] && name[0...5] == 'haml:'
          output = (self.children || []).inject("") do |out, child|
            if child.text?
              text = CGI.unescapeHTML(child.inner_text).strip
              text.gsub!(/(^[- ]+)|([- ]+$)/, '')
              next out if text.empty?
              out + tab_prefix + send("haml_tag_#{name[5..-1]}", text, tab_prefix)
            elsif child.name[0...10] == 'haml:block'
              out + child.to_haml(tabs + 1, options)
            elsif child.name[0...5] == 'haml:'
              out + child.to_haml(tabs, options)
            else
              out + child.to_haml(tabs, options)
            end
          end
          return output
        end

        output += "%#{name}" unless name == 'div' &&
          (static_id?(options) || static_classname?(options))

        if attributes
          if static_id?(options)
            output += "##{attributes['id']}"
            remove_attribute('id')
          end
          if static_classname?(options)
            attributes['class'].split(' ').each { |c| output += ".#{c}" }
            remove_attribute('class')
          end
          output += haml_attributes(options) if attributes.length > 0
        end

        (self.children || []).inject(output + "\n") do |output, child|
          output + child.to_haml(tabs + 1, options)
        end
      end

      private
      
      def dynamic_attributes
        @dynamic_attributes ||= begin
          Haml::Util.map_hash(attributes) do |name, value|
            next if value.empty?
            full_match = nil
            ruby_value = value.gsub(%r{<haml:loud>\s*(.+?)\s*</haml:loud>}) do
              full_match = $`.empty? && $'.empty?
              full_match ? $1: "\#{#{$1}}"
            end
            next if ruby_value == value
            [name, full_match ? ruby_value : %("#{ruby_value}")]
          end
        end
      end

      def haml_tag_loud(text, tab_prefix = '')
        if text =~ /\n/
          lines = text.strip.split(/\n+/)
          pad_size = lines.map { |line| line.length }.max + 1
          out = lines.map { |line| tab_prefix + "  " + line.ljust(pad_size) + '|' }.join("\n")
          out[0...4] = "= "
          out + "\n"
        else
          "= #{text.gsub(/\n\s*/, ' ').strip}\n"
        end
      end

      def haml_tag_silent(text, tab_prefix = '')
        text.strip.split("\n").map { |line| "- #{line.strip}" }.join("\n#{tab_prefix}") + "\n"
      end
      
      def haml_tag_block(text, tab_prefix = '')
        "#{text.strip}\n"
      end

      def static_attribute?(name, options)
        attributes[name] and !dynamic_attribute?(name, options)
      end
      
      def dynamic_attribute?(name, options)
        options[:rhtml] and dynamic_attributes.key?(name)
      end
      
      def static_id?(options)
        static_attribute?('id', options)
      end
      
      def static_classname?(options)
        static_attribute?('class', options)
      end

      # Returns a string representation of an attributes hash
      # that's prettier than that produced by Hash#inspect
      def haml_attributes(options)
        attrs = attributes.map do |name, value|
          value = dynamic_attribute?(name, options) ? dynamic_attributes[name] : value.inspect
          name = name.index(/\W/) ? name.inspect : ":#{name}"
          "#{name} => #{value}"
        end
        "{ #{attrs.join(', ')} }"
      end
    end

    private
    
    TOKEN_DELIMITER = '__oHg5SJYRHA0__'
    
    def convert_to_hamlified_markup(string)      
      output = ''
      compiler = ERB::HamlCompiler.new(nil)
      compiler.insert_cmd = compiler.put_cmd = '_erbout.concat'

      lines = compiler.compile(string, TOKEN_DELIMITER).split(TOKEN_DELIMITER)
      lines.each do |code|
        code.gsub!(/(^[- ]+)|([- ]+$)/, '')
        output << if code[0...15] == '_erbout.concat '
          code[0...15] = ''
          eval(code)
        elsif code =~ /^_erbout\.concat\(\((.*)\)\.to_s\)$/m
          "<haml:loud>#{$1}</haml:loud>"
        elsif code == 'end'
          "</haml:block></haml:silent>"
        else
          begin
            ParseTree.translate(code)
            "<haml:silent>#{code}</haml:silent>"
          rescue Exception => e # For some reason, trying to catch SyntaxError doesn't work
            "<haml:silent>#{code}<haml:block>"
          end
        end
      end
      output
    end

  end
end
