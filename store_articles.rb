require 'mongo'


def datetime_to_mongo(dt)
  Time.utc(dt.year, dt.month, dt.day, dt.hour, dt.min)
end

class ArticleStore
  include Mongo

  def initialize
    @db = MongoClient.new('localhost', 27017).db('lnexplorer')
    @articles = @db.collection('articles')
    @entities = @db.collection('entities')
    @tags     = @db.collection('tags')
  end

  def store_article(article)

    tp = article.tagged_people.map do |p|
      p_h = p.to_h
      p_h[:_id] = p_h[:url]
      p_h
    end

    tp.each { |p|
      @entities.insert p unless @entities.count(:query => { :_id => p[:_id]}) == 1
    }

    if @articles.count(:query => { :_id => a_h[:_id] }) == 0
      a_h = article.to_h
      a_h.delete(:tagged_people); a_h.delete(:detected_entities)
      a_h[:entities] = tp.map { |p| BSON::DBRef.new('entities', p[:_id]) }
      a_h[:date] = datetime_to_mongo(a_h[:date])
      a_h[:_id] = a_h[:url]
      a_h[:tags] = []
      @articles.insert(a_h)
    end
    a = @articles.find({ :_id => article.url })

    # a_h[:tags][0][:_id] = a[:tag].delete(:id)
    # @tags.insert(a_h[:tags].first) unless @tags.count(:query => {:_id => a_h[:tags][0][:_id] }) == 1
    # a_h[:]

  end

end

if __FILE__ == $0
  require_relative './lanacion_scraper.rb'
  sc = LaNacionTagScraper.new
  st = ArticleStore.new
  sc.tag_articles(ARGV.shift).each do |article|
    st.store_article(article)
  end
end
