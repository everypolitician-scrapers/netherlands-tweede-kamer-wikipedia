#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def noko_between(noko, from_id, to_id)
  section_start = noko.css('#' + from_id)
  raise "Can't find start section #{from_id}" if section_start.empty?

  section_end = noko.css('#' + to_id)
  raise "Can't find end section #{to_id}" if section_end.empty?

  section_start.xpath('.//preceding::*').remove
  section_end.xpath('.//following::*').remove
  noko
end

def reverse_date(str)
  str.split('-').reverse.map { |d| sprintf '%02d', d }.join('-')
end

def scrape_term(url)
  noko = noko_for(url)
  list = noko_between(noko, 'Samenstelling_van_de_kamer_sinds_12_september_2012', 'Bijzonderheden')
  list.css('h3').each do |h3|
    party_info = h3.children.first
    party = party_info.children.first.text
    party_wikiname = party_info.xpath('.//a[not(@class="new")]/@title').text

    people_lists = h3.xpath('following::h3 | following::ul').slice_before { |e| e.name == 'h3' }.first
    people_lists.each do |people_list|
      people_list.css('li').each do |person|
        name = person.children.first.children.first.text
        wikiname = person.xpath('.//a[not(@class="new")]/@title').text
        dates = [{ type: 'start', date: '' }]

        person.text.scan(/\(([^\)]+)\)/).flatten.each do |bracketed|
          if sd = bracketed[/↑ (.*)/, 1]
            dates << { type: 'end', date: reverse_date(sd) }
          elsif sd = bracketed[/↓ (.*)/, 1]
            dates << { type: 'start', date: reverse_date(sd) }
          end
        end

        dates << { type: 'end', date: '' } unless dates[-1] && dates[-1][:type] == 'end'
        dates.shift if dates[1] && dates[1][:type] == 'start'

        dates.each_slice(2).each do |from, to|
          data = {
            name:           name,
            wikiname:       wikiname,
            party:          party,
            party_wikiname: party_wikiname,
            term:           2012,
            start_date:     from[:date],
            end_date:       to[:date],
          }
          ScraperWiki.save_sqlite(%i(name wikiname party start_date term), data)
        end
      end
    end
  end
end

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
scrape_term('https://nl.wikipedia.org/wiki/Samenstelling_Tweede_Kamer_2012-heden')
