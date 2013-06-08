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

    if @articles.count(:query => { :_id => article[:url] }) == 0
      a_h = article.to_h
      a_h.delete(:tagged_people); a_h.delete(:detected_entities)
      a_h[:entities] = tp.map { |p| BSON::DBRef.new('entities', p[:_id]) }
      a_h[:date] = datetime_to_mongo(a_h[:date])
      a_h[:_id] = a_h[:url]
      a_h[:tags] = []
      @articles.insert(a_h)
    end

    # update tags if needed
    a = @articles.find_one( :_id => article.url )
    unless a['tags'].any? { |t| t.object_id == article[:tags].first[:id] }
      # tag exists?
      t = @tags.find_one(:_id => article[:tags].first[:id])
      if t.nil?
        at = article[:tags].first
        at[:_id] = at.delete(:id)
        @tags.insert(at)
        t = @tags.find_one('_id' => at[:_id])
      end

      @articles.update({ '_id' => a['_id'] },
                       {
                         '$set' => {
                           'tags' => a['tags'] + [BSON::DBRef.new('tags', t['_id'])]
                         }
                       })
    end
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
