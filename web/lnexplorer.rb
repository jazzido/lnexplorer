require 'json'
require 'time'

require 'cuba'
require 'cuba/render'
require 'mongo'


 class Time
   def to_json(*args)
     #"new Date(\"#{self}\")"
     self.iso8601.to_json
   end
 end

class JSONResponse
  def initialize(app)
    @app = app
  end

  def call(env)
    res = @app.call(env)
    res[1] = {"Content-Type"=>"application/json; charset=utf-8"}
    res
  end
end

DB = Mongo::MongoClient.new('localhost', 27017).db('lnexplorer')
ARTICLES = DB.collection 'articles'

class API < Cuba; end
API.use JSONResponse
API.define do
  on get do
    on 'tags/:tag_id/histogram' do |tag_id|

      hist = ARTICLES.group(
                            :keyf => "function(doc) {
            return { date: new Date(doc.date.getFullYear(), doc.date.getMonth(), doc.date.getDate()) };
        }",
                            :initial => { 'count' => 0 },
                            :cond => { 'tags.$id' => tag_id },
                            :reduce => "function(obj, prev) { prev.count++; } ")

        res.write hist.sort_by { |d| d['date'] }.to_json
    end

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
      res.write tags.to_json
    end
  end
end


class LNExplorer < Cuba; end
LNExplorer.use Rack::Static, root: 'web/public', urls: ["/css", "/js", "/index.html"]
LNExplorer.define do

  on 'api' do
    run API
  end

  on get do
    on root do
      res.write File.open(File.join(File.dirname(__FILE__), 'public', 'index.html')).read
    end
  end

end
