require 'json'

require 'cuba'
require 'cuba/render'
require 'mongo'


Cuba.plugin Cuba::Render
Cuba.use Rack::Reloader

Cuba.use Rack::Static, root: 'public', urls: ["/css", "/js", "/timelines"]
Cuba.settings[:render][:views] = File.join(File.dirname(__FILE__), 'views')

DB = Mongo::MongoClient.new('localhost', 27017).db('lnexplorer')
ARTICLES = DB.collection 'articles'

class Time
  def to_json(*args)
    "new Date(\"#{self}\")"
  end
end

Cuba.define do
  on get do

    on 'tags' do
      tags = ARTICLES.aggregate([{
                                   '$project' => {
                                     'tags' => 1,
                                     'date' => 1
                                   }
                                 },
                                 { '$unwind' => '$tags' },
                                 { '$group' => {
                                     '_id' => '$tags',
                                     'count' => { '$sum' => 1 },
                                     'from' => { '$min' => '$date' },
                                     'to' => { '$max' => '$date' },
                                   }
                                 }])
        .map { |t| t.merge('tag' => DB.dereference(t['_id'])) }
      res['Content-Type'] = 'application/json'
      res.write tags.to_json
    end

    on 'tag/histogram/:tag_id' do |tag_id|

    end

    on root do
      res.write view('index.html', tags: tags)
    end

  end
end
