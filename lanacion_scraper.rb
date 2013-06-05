require 'mechanize'
require 'json'
require 'logger'
require 'ostruct'
require 'freeling-analyzer'

# remove the byte order mark
def remove_BOM(str)
  str.force_encoding('utf-8').gsub("\xEF\xBB\xBF".force_encoding('utf-8'), '')
end

class Struct
  def to_json(*a)
    self.members.reduce({}) { |memo, m|
      memo[m] = self[m]
      memo
    }.to_json(*a)
  end
end

LaNacionArticle = Struct.new(:url, :title, :body, :tagged_people)
LaNacionTaggedPerson = Struct.new(:name, :url, :photo_url)

class LaNacionTagScraper

  HOST = 'www.lanacion.com.ar'
  ACUMULADOS_LIST_TMPL = "http://#{HOST}/acumuladosTagAjax-p%s-%s-15"

  def initialize
    @agent = Mechanize.new
    @agent.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.93 Safari/537.36'
    @logger = Logger.new(STDERR)
  end

  def tag_articles(tag)
    tag_id = /.+-t(\d+)/.match(tag)[1]
    page_num = 1

    @logger.debug('Scraping tag: #{tag}')

    Enumerator.new do |yielder|
      while true
        page = @agent.get ACUMULADOS_LIST_TMPL % [page_num, tag_id]
        articles = JSON.parse remove_BOM(page.body)

        break if articles['notas'].empty?

        articles['notas'].each do |n|
          yielder.yield scrape_article(n['nota']['url'])
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
#    require 'debugger'; debugger
#    puts article.to_json
    named_entities = FreeLing::Analyzer.new(article.body, :server_host => 'localhost:50005')
      .tokens
      .select { |t| t.tag.start_with?('NP') && t.prob > 0.9 }

    puts article.tagged_people.inspect

    puts named_entities.map(&:form).uniq.inspect

  end
end
