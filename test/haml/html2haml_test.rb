#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'
require 'haml/html'

class Html2HamlTest < Test::Unit::TestCase

  def test_empty_render_should_remain_empty
    assert_equal '', render('')
  end

  def test_id_and_class_should_be_removed_from_hash
    assert_equal '%span#foo.bar', render('<span id="foo" class="bar"> </span>')
  end

  def test_no_tag_name_for_div_if_class_or_id_is_present
    assert_equal '#foo', render('<div id="foo"> </div>')
    assert_equal '.foo', render('<div class="foo"> </div>')
  end

  def test_multiple_class_names
    assert_equal '.foo.bar.baz', render('<div class=" foo  bar  baz "> </div>')
  end

  def test_should_have_pretty_attributes
    assert_equal_attributes('%input{ :type => "text", :name => "login" }',
      render('<input type="text" name="login" />'))
    assert_equal_attributes('%meta{ "http-equiv" => "Content-Type", :content => "text/html" }',
      render('<meta http-equiv="Content-Type" content="text/html" />'))
  end

  def test_sqml_comment
    assert_equal "/\n  IE sucks", render('<!-- IE sucks -->')
  end

  def test_rhtml
    assert_equal '- foo = bar', render_rhtml('<% foo = bar %>')
    assert_equal '- foo = bar', render_rhtml('<% foo = bar -%>')
    assert_equal '= h @item.title', render_rhtml('<%=h @item.title %>')
    assert_equal '= h @item.title', render_rhtml('<%=h @item.title -%>')
  end
  
  def test_rhtml_with_html_special_chars
    assert_equal '= 3 < 5 ? "OK" : "Your computer is b0rken"',
      render_rhtml(%Q{<%= 3 < 5 ? "OK" : "Your computer is b0rken" %>})
  end
  
  def test_rhtml_in_class_attribute
    assert_equal "%div{ :class => dyna_class }\n  I have a dynamic attribute",
      render_rhtml(%Q{<div class="<%= dyna_class %>">I have a dynamic attribute</div>})
  end
  
  def test_rhtml_in_id_attribute
    assert_equal "%div{ :id => dyna_id }\n  I have a dynamic attribute",
      render_rhtml(%Q{<div id="<%= dyna_id %>">I have a dynamic attribute</div>})
  end
  
  def test_rhtml_in_attribute_results_in_string_interpolation
    assert_equal %(%div{ :id => "item_\#{i}" }\n  Ruby string interpolation FTW),
      render_rhtml(%Q{<div id="item_<%= i %>">Ruby string interpolation FTW</div>})
  end
  
  def test_rhtml_in_attribute_with_trailing_content
    assert_equal %(%div{ :class => "\#{12}!" }\n  Bang!),
      render_rhtml(%Q{<div class="<%= 12 %>!">Bang!</div>})
  end
  
  def test_rhtml_in_attribute_to_multiple_interpolations
    assert_equal %(%div{ :class => "\#{12} + \#{13}" }\n  Math is super),
      render_rhtml(%Q{<div class="<%= 12 %> + <%= 13 %>">Math is super</div>})
  end
  
  def test_whitespace_eating_erb_tags
    assert_equal %(- form_for),
      render_rhtml(%Q{<%- form_for -%>})
  end

  def test_blocks_and_consuming_end_tags
    html = <<-HTML.gsub(/^    /, '')
    <% if @post %>
      <% @post.comments.each do |comment| -%>
        <p><%= comment.name %></p>
      <% end -%>
    <% end %>
    HTML
    expected = <<-EOS.gsub(/^    /, '').strip
    - if @post
      - @post.comments.each do |comment|
        %p
          = comment.name
    EOS
    assert_equal expected, render_rhtml(html)
  end

  def test_content_for_block
    html = <<-HTML.gsub(/^    /, '')
    <% content_for :header do %>
      My Header
    <% end %>
    HTML
    expected = <<-RUBY.gsub(/^    /, '').strip
    - content_for :header do
      My Header
    RUBY
    assert_equal expected, render_rhtml(html)
  end
  
  def test_intermediate_format_with_load_and_silent_tags
    html = <<-HTML.gsub(/^    /, '')
    <p>Hi there</p>
    <haml:silent>
      if @post
      <haml:loud>@post.title</haml:loud>
      else
      <haml:loud>"Unknown"</haml:loud>
    </haml:silent>
    <haml:silent> content_for :header do 
      <haml:html>My Header</haml:html>
    </haml:silent>
    <p>Goodbye</p>
    HTML
    expected = <<-HAML.gsub(/^    /, '').strip
    %p
      Hi there
    - if @post
      = @post.title
    - else
      = "Unknown"
    - content_for :header do
      My Header
    %p
      Goodbye
    HAML
    assert_equal expected, render_rhtml(html)
  end

  def test_cdata
    assert_equal(<<HAML.strip, render(<<HTML))
%p
  :cdata
    <a foo="bar" baz="bang">
    <div id="foo">flop</div>
    </a>
HAML
<p><![CDATA[
  <a foo="bar" baz="bang">
    <div id="foo">flop</div>
  </a>
]]></p>
HTML
  end

  # Encodings

  unless Haml::Util.ruby1_8?
    def test_encoding_error
      render("foo\nbar\nb\xFEaz".force_encoding("utf-8"))
      assert(false, "Expected exception")
    rescue Haml::Error => e
      assert_equal(3, e.line)
      assert_equal('Invalid UTF-8 character "\xFE"', e.message)
    end

    def test_ascii_incompatible_encoding_error
      template = "foo\nbar\nb_z".encode("utf-16le")
      template[9] = "\xFE".force_encoding("utf-16le")
      render(template)
      assert(false, "Expected exception")
    rescue Haml::Error => e
      assert_equal(3, e.line)
      assert_equal('Invalid UTF-16LE character "\xFE"', e.message)
    end
  end

  protected

  def render(text, options = {})
    Haml::HTML.new(text, options).render.rstrip
  end

  def render_rhtml(text)
    render(text, :rhtml => true)
  end

  def assert_equal_attributes(expected, result)
    expected_attr, result_attr = [expected, result].map { |s| s.gsub!(/\{ (.+) \}/, ''); $1.split(', ').sort }
    assert_equal expected_attr, result_attr
    assert_equal expected, result
  end
end
