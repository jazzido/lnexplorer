$(function() {

    var Tag = Backbone.Model.extend({
        // fuck you JSON, make up your mind about date formats already.
        parse: function(response) {
            var _parseDate = function(str) {
                a = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}(?:\.\d*)?)Z$/.exec(str);
                if (a) {
                    return new Date(Date.UTC(+a[1], +a[2] - 1, +a[3], +a[4],
                                             +a[5], +a[6]));
                }
                else {
                    return str;
                }
            };
            this.set(_.extend(_.omit(response,
                                     ['from', 'to', '_id']),
                              {
                                  from: _parseDate(response.from),
                                  to:   _parseDate(response.to)
                              }));
        }
    });

    var TagList = Backbone.Collection.extend({
        model: Tag,
        url: '/api/tags',
    });

    var Tags = new TagList;

    var LineChartView = Backbone.View.extend({
        tagName: 'div',
        id: 'linechart',
        width: 500,
        height: 150,

        createSVG: function() {
            this.linechart = d3.select(this.tagName + '#' + this.id).append('svg')
                .attr('width', this.width)
                .attr('height', this.height);

            var linechart_x = d3.time.scale()
            .domain([_.min(this.collection.models,
                           function(d) {
                               return d.get('from');
                           }).get('from'),
                     _.max(this.collection.models,
                           function(d) {
                               return d.get('to');
                           }).get('to')])
            .range([0, this.width]);

            var linechart_xaxis = d3.svg.axis()
                                         .scale(linechart_x)
                                         .orient('bottom');

            var linechart_y = d3.scale.linear()
                                      .domain([0, 100])
                                      .range([0, this.height]);

            this.linechart.append('g')
                          .attr('class', 'axis')
                          .call(linechart_xaxis);
        },

        render: function() {
            this.createSVG();
            this.$el.html('cacaurulo');
            return this;
        }
    });

    var TagView = Backbone.View.extend({
        tagName: 'li',
        template: _.template("<a href=\"#\"><%= tag.title %></a>"),
        render: function() {
            this.$el.html(this.template(this.model.toJSON()));
            return this;
        }
    });

    var AppView = Backbone.View.extend({
        el: $('#container'),

        initialize: function() {
            var _this = this;
            Tags.fetch().done(function() {
                Tags.each(function(t) {
                    var v = new TagView({model: t});
                    $('#tags').append(v.render().el);
                }, _this);
                var v = new LineChartView({collection: Tags});
                console.log(v.render().el);
            });
        }

    });

    var App = new AppView;

});
