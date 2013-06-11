require 'mongo'

def datetime_to_mongo(dt)
  Time.utc(dt.year, dt.month, dt.day, dt.hour, dt.min)
end

class ArticleStore
  include Mongo

  attr_reader :articles, :entities

  def initialize
    @db = MongoClient.new('localhost', 27017).db('lnexplorer')
    @articles = @db.collection('articles')
    @entities = @db.collection('entities')
    @tags     = @db.collection('tags')
  end

  def find_untagged_entities(article, known_entities_hash)
    known_entities_hash.select { |k,v| article['body'].include?(k) && \
      !article['entities'].any? { |e| e.object_id == v['_id'] }
    }.values
  end

  def tag_untagged_articles!
    known = Hash[@entities.find.map { |e| e['name'] }.zip(@entities.find)]
    known.delete(nil)

    @articles.find.each { |a|
      new = self.find_untagged_entities(a, known).map { |e|
        BSON::DBRef.new('entities', e['_id'])
      }
      a['entities'] += new
      @articles.update({ '_id' => a['_id'] },
                       {
                         '$set' => {
                           'entities' => a['entities'] + new
                         }
                       })
    }
  end

  def store_article(article)
    tp = article.tagged_people.map do |p|
      p_h = p.to_h
      p_h[:_id] = p_h[:url]
      p_h
    end

    tags = article.tags.map do |t|
      t_h = t.to_h
      t_h[:_id] = t_h[:id]
      t_h
    end

    tp.each { |p|
      @entities.insert p unless @entities.count(:query => { :_id => p[:_id]}) == 1
    }

    tags.each { |p|
      @tags.insert p unless @tags.count(:query => { :_id => p[:_id]}) == 1
    }

    a = @articles.find_one( :_id => article[:url] )
    if a.nil?
      a_h = article.to_h
      a_h.delete(:tagged_people); a_h.delete(:detected_entities)
      a_h[:entities] = tp.map { |p| BSON::DBRef.new('entities', p[:_id]) }
      a_h[:tags] = tags.map { |p| BSON::DBRef.new('tags', p[:_id]) }
      a_h[:date] = datetime_to_mongo(a_h[:date])
      a_h[:_id] = a_h[:url]
      @articles.insert(a_h)
    else # only update tags and entities
      @articles.update({ '_id' => a['_id'] },
                       {
                         '$set' => {
                           'tags' => tags.map { |p| BSON::DBRef.new('tags', p[:_id]) },
                           'entities' => tp.map { |p| BSON::DBRef.new('entities', p[:_id]) }
                         }
                       })
    end
  end
end

if __FILE__ == $0
  require_relative './lanacion_scraper.rb'
  sc = LaNacionTagScraper.new
  st = ArticleStore.new
  sc.entity_articles(ARGV.shift).each do |article|
    st.store_article(article)
  end
end
