# -*- coding: utf-8 -*-
require 'json'
require 'logger'
require 'date'

require 'mechanize'

# remove the byte order mark
def remove_BOM(str)
  str.force_encoding('utf-8').gsub("\xEF\xBB\xBF".force_encoding('utf-8'), '')
end

MONTHS_TRANSLATED = {"enero"=>"january", "febrero"=>"february", "marzo"=>"march", "abril"=>"april", "mayo"=>"may", "junio"=>"june", "julio"=>"july", "agosto"=>"august", "septiembre"=>"september", "octubre"=>"october", "noviembre"=>"november", "diciembre"=>"december"}
SPANISH_MONTHS_RE = Regexp.new(MONTHS_TRANSLATED.keys.compact.join('|'))
SPANISH_DAYS_RE   = Regexp.new("lunes|martes|miércoles|jueves|viernes|sábado|domingo")

def parse_spanish_date(str)
  DateTime.parse(str.downcase.gsub(' de ', ' ')
                                .gsub(SPANISH_MONTHS_RE, MONTHS_TRANSLATED)
                                .gsub(SPANISH_DAYS_RE, '')
                                .strip)
end

class Struct
  def to_h
    self.members.reduce({}) { |memo, m|
      memo[m] = self[m]
      memo
    }.merge({:_type => self.class.to_s })
  end

  def to_json(*a)
     to_h.to_json(*a)
  end
end

LaNacionArticle = Struct.new(:url, :title, :body, :date, :tagged_people, :detected_entities, :tags)
LaNacionTaggedPerson = Struct.new(:name, :url, :photo_url)
LaNacionTag = Struct.new(:title, :id)
DetectedEntity = Struct.new(:name, :lemma, :eagle_tag)

class LaNacionTagScraper

  HOST = 'www.lanacion.com.ar'
  ACUMULADOS_LIST_TMPL = "http://#{HOST}/acumuladosTagAjax-p%s-%s-15"

  def initialize
    @agent = Mechanize.new
    @agent.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.93 Safari/537.36'
    @logger = Logger.new(STDERR)
  end

  def entity_articles(entity)
    return [] if entity.nil?
    entity_id = /.+-t(\d+)/.match(entity)[1]
    page_num = 1

    @logger.debug("Scraping entity: #{entity}")

    Enumerator.new do |yielder|
      while true
        page = @agent.get ACUMULADOS_LIST_TMPL % [page_num, entity_id]
        articles = JSON.parse remove_BOM(page.body)

        break if articles['notas'].empty?

        articles['notas'].each do |n|
          begin
            article = scrape_article(n['nota']['url'])
            article[:tags] = []
          rescue
            # could not scrape, I don't care
            next
          end
          yielder.yield article
        end
        page_num += 1
      end
    end
  end

  def tag_articles(tag)
    tag_id = /.+-t(\d+)/.match(tag)[1]
    page_num = 1

    @logger.debug("Scraping tag: #{tag}")

    # get tag title
    tag_title = @agent.get('http://' + HOST + '/' + tag).search('h1').text

    Enumerator.new do |yielder|
      while true
        page = @agent.get ACUMULADOS_LIST_TMPL % [page_num, tag_id]
        articles = JSON.parse remove_BOM(page.body)

        break if articles['notas'].empty?

        articles['notas'].each do |n|
          begin
            article = scrape_article(n['nota']['url'])
          rescue
            # could not scrape, I don't care
            next
          end
          article[:tags] = [LaNacionTag.new(tag, tag_title)]
          yielder.yield article
        end
        page_num += 1
      end
    end
  end

  def scrape_article(url)
    @logger.debug "getting article #{url}"
    page = @agent.get "http://#{HOST}#{url}"

    LaNacionArticle.new(url,
                        page.search('article h1').text,
                        page.search('article section#cuerpo p').map(&:text).join('\n\n'),
                        parse_spanish_date(page.search('//span[@itemprop="datePublished"]').text),
                        page.search('//article[@itemtype="http://schema.org/Person"]').map { |e|
                          LaNacionTaggedPerson.new(e.search('span[@itemprop="name"]').text,
                                                   'http://' + HOST + e.search('a[@itemprop="url"]/@href').to_s,
                                                   e.search('span[@itemprop="image"]').text)
                        })
  end
end

if __FILE__ == $0
  s = LaNacionTagScraper.new
  s.tag_articles(ARGV.shift).each do |article|
    named_entities = FreeLing::Analyzer.new(article.body, :server_host => 'localhost:50005')
      .tokens
      .select { |t| t.tag.start_with?('NP') && t.prob > 0.9 }

    puts article.inspect

    puts named_entities.map(&:form).uniq.inspect

  end
end
