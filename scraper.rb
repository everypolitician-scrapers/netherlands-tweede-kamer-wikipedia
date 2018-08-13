#!/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require_rel 'lib'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def to_date
    return if to_s.tidy.empty?
    Date.parse(self).to_s rescue binding.pry
  end
end

# Known good at https://nl.wikipedia.org/w/index.php?title=Samenstelling_Tweede_Kamer_2017-heden&oldid=51922042
class MembersPage < Scraped::HTML
  decorator RemoveFootnotes
  decorator WikidataIdsDecorator::Links

  field :members do
    noko.xpath('//table[.//th[contains(.,"lidmaatschap")]]//tr[td]').map { |tr| fragment(tr => MemberRow).to_h }
  end
end

class MemberRow < Scraped::HTML
  field :id do
    tds[0].css('a/@wikidata').map(&:text).first
  end

  field :name do
    tds[0].css('a').map(&:text).first
  end

  field :party_id do
    party_link.attr('wikidata')
  end

  field :party do
    party_link.text.tidy
  end

  field :start_date do
    tds[1].text.to_date
  end

  field :end_date do
    tds[2].text.to_date
  end

  private

  def tds
    noko.css('td')
  end

  def party_link
    noko.xpath('preceding::span[@class="mw-headline"]').last.css('a').first
  end

  def reverse_date(str)
    str.split('-').reverse.map { |d| '%02d' % d }.join('-')
  end
end

url = 'https://nl.wikipedia.org/wiki/Samenstelling_Tweede_Kamer_2017-heden'
ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
Scraped::Scraper.new(url => MembersPage).store(:members, index: %i[name party])
