#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class ListPage < Scraped::HTML
  field :parties do
    composition.css('h3').map do |h3|
      fragment h3 => PartySection
    end
  end

  private

  def composition
    noko_between(noko, 'Samenstelling_van_de_kamer_sinds_12_september_2012', 'Bijzonderheden')
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
end

class PartySection < Scraped::HTML
  field :party do
    party_info.children.first.text.split('(').first.tidy
  end

  field :party_wikiname do
    party_info.xpath('.//a[not(@class="new")]/@title').text
  end

  field :members do
    following_lists.flat_map { |e| e.css('li') }.map do |li|
      fragment li => MemberSection
    end
  end

  private

  def party_info
    noko.children.first
  end

  def following_lists
    noko.xpath('following::h3 | following::ul').slice_before { |e| e.name == 'h3' }.first
  end
end

class MemberSection < Scraped::HTML
  field :name do
    noko.children.first.children.first.text
  end

  field :wikiname do
    noko.xpath('.//a[not(@class="new")]/@title').text
  end

  field :memberships do
    dates = [{ type: 'start', date: '' }]
    noko.text.scan(/\(([^\)]+)\)/).flatten.each do |bracketed|
      if sd = bracketed[/↑ (.*)/, 1]
        dates << { type: 'end', date: reverse_date(sd) }
      elsif sd = bracketed[/↓ (.*)/, 1]
        dates << { type: 'start', date: reverse_date(sd) }
      end
    end

    dates << { type: 'end', date: '' } unless dates[-1] && dates[-1][:type] == 'end'
    dates.shift if dates[1] && dates[1][:type] == 'start'
    dates.each_slice(2).map do |from, to|
      { start_date: from[:date], end_date: to[:date] }
    end
  end

  private

  def reverse_date(str)
    str.split('-').reverse.map { |d| '%02d' % d }.join('-')
  end
end

def term_data(url)
  page = ListPage.new(response: Scraped::Request.new(url: url).response)
  page.parties.map(&:to_h).flat_map do |party|
    party.delete(:members).map(&:to_h).flat_map do |member|
      member.delete(:memberships).map do |membership|
        member.merge(party).merge(term: 2012).merge(membership)
      end
    end
  end
end

data = term_data('https://nl.wikipedia.org/wiki/Samenstelling_Tweede_Kamer_2012-2017')
# puts data

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
ScraperWiki.save_sqlite(%i[name wikiname party start_date term], data)
