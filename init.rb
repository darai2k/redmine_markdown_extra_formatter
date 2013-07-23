# Redmine Markdown Extra formatter
require 'redmine'
require File.expand_path(File.dirname(__FILE__)) + '/app/helpers/redmine_markdown_extra_formatter/helper'
require File.expand_path(File.dirname(__FILE__)) + '/lib/redmine_markdown_extra_formatter/wiki_formatter'

Rails.logger.info 'Starting Markdown Extra formatter for RedMine'

Redmine::Plugin.register :redmine_markdown_extra_formatter do
  name 'Markdown Extra formatter'
  author 'Junya Ogura'
  description 'This provides Markdown Extra as a wiki format'
  version '0.0.6'

  wiki_format_provider 'Markdown Extra', RedmineMarkdownExtraFormatter::WikiFormatter, RedmineMarkdownExtraFormatter::Helper
end
