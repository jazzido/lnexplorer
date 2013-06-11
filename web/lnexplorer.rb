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

DB = if ENV['MONGOLAB_URI']
  mongo_uri = ENV['MONGOLAB_URI']
  client = Mongo::MongoClient.from_uri(mongo_uri)
  client.db(ENV['MONGOLAB_DB'])
else
  Mongo::MongoClient.new('localhost', 27017).db('lnexplorer')
end

ARTICLES = DB.collection 'articles'

class API < Cuba; end
API.use JSONResponse
API.define do
  on get do

    on 'entities/:entity_id/date_counts' do |entity_id|
      cond = { 'entities.$id' => entity_id }
      cond['date'] = { '$gte' => Time.parse(req.params['from'])} if req.params['from']
      cond['date'] = { '$lte' => Time.parse(req.params['to'])} if req.params['to']

      hist = ARTICLES.group(
                            :keyf => "function(doc) {
                                        return { date: new Date(doc.date.getFullYear(), doc.date.getMonth(), doc.date.getDate()) };
                                      }",
                            :initial => { 'count' => 0 },
                            :cond => cond,
                            :reduce => "function(obj, prev) { prev.count++; } ")
                     .sort_by { |d| d['date'] }
                     .reduce([]) { |r, value| # fill gaps
                       unless r.size == 0
                         x = value['date'] - 60*60*24
                         y = r.last['date']
                         while y != x do
                           r << { 'date' => x, 'count' => 0 }
                           x -= 60*60*24
                         end
                       end
                       r << value
                     }
                     .sort_by { |d| d['date'] }

      res.write hist.to_json
    end

    on 'entities' do
      cond = { 'date' => {}}
      cond['date']['$gte'] = Time.parse(req.params['from']) if req.params['from']
      cond['date']['$lte'] = Time.parse(req.params['to']) if req.params['to']

      query = [{
                 '$project' => {
                   'entities' => 1,
                   'date' => 1
                 }
               },
               { '$unwind' => '$entities' },
               { '$group' => {
                   '_id' => '$entities',
                   'count' => { '$sum' => 1 },
                   'from' => { '$min' => '$date' },
                   'to' => { '$max' => '$date' },
                 }
               },
               { '$sort' => { 'count' => 1 } }
              ]

       if cond['date'] != {}
         query.insert(1, { '$match' => cond})
       end

      entities = ARTICLES.aggregate(query)
        .map { |e| e.merge('entity' => DB.dereference(e['_id'])) }.reverse!
      res.write entities.to_json
    end


    on 'tags/:tag_id/date_counts' do |tag_id|
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
      cond = { 'date' => {}}
      cond['date']['$gte'] = Time.parse(req.params['from']) if req.params['from']
      cond['date']['$lte'] = Time.parse(req.params['to']) if req.params['to']

      query = [{
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
               }]

      if cond['date'] != {}
        query.insert(2, { '$match' => cond})
      end

      tags = ARTICLES.aggregate(query)
        .map { |t| t.merge('tag' => DB.dereference(t['_id'])) }
      res.write tags.to_json
    end

  end
end


class LNExplorer < Cuba; end
LNExplorer.use Rack::ContentLength
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
