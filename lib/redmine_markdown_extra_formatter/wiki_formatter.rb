# -*- coding: utf-8 -*-
require 'bluefeather'
require 'coderay'

module BlueFeather
  class Parser

    # derived from bluefeather.rb

    TOCRegexp = %r{
      ^\{    # bracket on line-head
      [ ]*    # optional inner space
      ([<>])?
      toc

      (?:
        (?:
          [:]    # colon
          |      # or
          [ ]+   # 1 or more space
        )
        (.+?)    # $1 = parameter
      )?

      [ ]*    # optional inner space
      \}     # closer
      [ ]*$   # optional space on line-foot
    }ix

    TOCStartLevelRegexp = %r{
      ^
      (?:              # optional start
        h
        ([1-6])        # $1 = start level
      )?

      (?:              # range symbol
        [.]{2,}|[-]    # .. or -
      )

      (?:              # optional end
        h?             # optional 'h'
        ([1-6])        # $2 = end level
      )?$
    }ix

    ### Transform any Markdown-style horizontal rules in a copy of the specified
    ### +str+ and return it.
    def transform_toc( str, rs )
      @log.debug " Transforming tables of contents"
      str.gsub(TOCRegexp){
        start_level = 1 # default
        end_level = 6

        param = $2
        if param then
          if param =~ TOCStartLevelRegexp then
            if !($1) and !($2) then
              rs.warnings << "illegal TOC parameter - #{param} (valid example: 'h2..h4')"
            else
              start_level = ($1 ? $1.to_i : 1)
              end_level = ($2 ? $2.to_i : 6)
            end
          else
            rs.warnings << "illegal TOC parameter - #{param} (valid example: 'h2..h4')"
          end
        end

        if rs.headers.first and rs.headers.first.level >= (start_level + 1) then
          rs.warnings << "illegal structure of headers - h#{start_level} should be set before h#{rs.headers.first.level}"
        end


        ul_text = "\n\n"
        div_class = 'toc'
        div_class << ' right' if $1 == '>'
        div_class << ' left' if $1 == '<'
        ul_text << "<ul class=\"#{div_class}\">"
        rs.headers.each do |header|
          if header.level >= start_level and header.level <= end_level then
            ul_text << "<li class=\"heading#{header.level}\"><a href=\"##{header.id}\">#{header.content_html}</a></li>\n"
          end
        end
        ul_text << "</ul>"
        ul_text << "\n"

        ul_text # output

      }
    end

    ### Apply Markdown anchor transforms to a copy of the specified +str+ with
    ### the given render state +rs+ and return it.
    def transform_anchors( str, rs )
      @log.debug " Transforming anchors"
      @scanner.string = str.dup
      text = ''

      # Scan the whole string
      until @scanner.empty?

        if @scanner.scan( /\[/ )
          link = ''; linkid = ''
          depth = 1
          startpos = @scanner.pos
          @log.debug " Found a bracket-open at %d" % startpos

          # Scan the rest of the tag, allowing unlimited nested []s. If
          # the scanner runs out of text before the opening bracket is
          # closed, append the text and return (wasn't a valid anchor).
          while depth.nonzero?
            linktext = @scanner.scan_until( /\]|\[/ )

            if linktext
              @log.debug "  Found a bracket at depth %d: %p" % [ depth, linktext ]
              link += linktext

              # Decrement depth for each closing bracket
              depth += ( linktext[-1, 1] == ']' ? -1 : 1 )
              @log.debug "  Depth is now #{depth}"

            # If there's no more brackets, it must not be an anchor, so
            # just abort.
            else
              @log.debug "  Missing closing brace, assuming non-link."
              link += @scanner.rest
              @scanner.terminate
              return text + '[' + link
            end
          end
          link.slice!( -1 ) # Trim final ']'
          @log.debug " Found leading link %p" % link



          # Markdown Extra: Footnote
          if link =~ /^\^(.+)/ then
            id = $1
            if rs.footnotes[id] then
              rs.found_footnote_ids << id
              label = "[#{rs.found_footnote_ids.size}]"
            else
              rs.warnings << "undefined footnote id - #{id}"
              label = '[?]'
            end

            text += %Q|<sup id="footnote-ref:#{id}"><a href="#footnote:#{id}" rel="footnote">#{label}</a></sup>|

          # Look for a reference-style second part
          elsif @scanner.scan( RefLinkIdRegexp )
            linkid = @scanner[1]
            linkid = link.dup if linkid.empty?
            linkid.downcase!
            @log.debug "  Found a linkid: %p" % linkid

            # If there's a matching link in the link table, build an
            # anchor tag for it.
            if rs.urls.key?( linkid )
              @log.debug "   Found link key in the link table: %p" % rs.urls[linkid]
              url = escape_md( rs.urls[linkid] )

              text += %{<a href="#{url}"}
              if rs.titles.key?(linkid)
                text += %{ title="%s"} % escape_md( rs.titles[linkid] )
              end
              text += %{>#{link}</a>}

            # If the link referred to doesn't exist, just append the raw
            # source to the result
            else
              @log.debug "  Linkid %p not found in link table" % linkid
              @log.debug "  Appending original string instead: "
              @log.debug "%p" % @scanner.string.byteslice( startpos-1 .. @scanner.pos-1 )

              rs.warnings << "link-id not found - #{linkid}"
              text += @scanner.string.byteslice( startpos-1 .. @scanner.pos-1 )
            end

          # ...or for an inline style second part
          elsif @scanner.scan( InlineLinkRegexp )
            url = @scanner[1]
            title = @scanner[3]
            @log.debug "  Found an inline link to %p" % url

            url = "##{link}" if url == '#' # target anchor briefing (since BlueFeather 0.40)

            text += %{<a href="%s"} % escape_md( url )
            if title
              title.gsub!( /"/, "&quot;" )
              text += %{ title="%s"} % escape_md( title )
            end
            text += %{>#{link}</a>}

          # No linkid part: just append the first part as-is.
          else
            @log.debug "No linkid, so no anchor. Appending literal text."
            text += @scanner.string.byteslice( startpos-1 .. @scanner.pos-1 )
          end # if linkid

        # Plain text
        else
          @log.debug " Scanning to the next link from %p" % @scanner.rest
          text += @scanner.scan( /[^\[]+/ )
        end

      end # until @scanner.empty?

      return text
    end
  end
end

module RedmineMarkdownExtraFormatter
  class WikiFormatter
    def initialize(text)
      @text = text
    end

    def to_html(&block)
      @macros_runner = block
      parsedText = BlueFeather.parse(@text)
      parsedText = inline_macros(parsedText)
      parsedText = syntax_highlight(parsedText)
    rescue => e
      return("<pre>problem parsing wiki text: #{e.message}\n"+
             "original text: \n"+
             @text+
             "</pre>")
    end

    MACROS_RE = /
          (!)?                        # escaping
          (
          \{\{                        # opening tag
          ([\w]+)                     # macro name
          (\(([^\}]*)\))?             # optional arguments
          \}\}                        # closing tag
          )
        /x

    def inline_macros(text)
      text.gsub!(MACROS_RE) do
        esc, all, macro = $1, $2, $3.downcase
        args = ($5 || '').split(',').each(&:strip)
        if esc.nil?
          begin
            @macros_runner.call(macro, args)
          rescue => e
            "<div class=\"flash error\">Error executing the <strong>#{macro}</strong> macro (#{e})</div>"
          end || all
        else
          all
        end
      end
      text
    end

    PreCodeClassBlockRegexp = %r{^<pre><code\s+class="(\w+)">\s*\n*(.+?)</code></pre>}m

    def syntax_highlight(str)
      str.gsub(PreCodeClassBlockRegexp) {|block|
        syntax = $1.downcase
        "<pre><code class=\"#{syntax.downcase} syntaxhl\">" +
        CodeRay.scan($2, syntax).html(:escape => true, :line_numbers => nil) +
        "</code></pre>"
      }
    end
  end
end
