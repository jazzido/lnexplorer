$(function() {

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


    var Tag = Backbone.Model.extend({
        initialize: function() {
            this.dateCounts = new (Backbone.Collection.extend({
                model: Backbone.Model.extend({
                    parse: function(response) {
                        this.set({
                            count: response.count,
                            date:  _parseDate(response.date)
                        });
                    }
                }),
            }));
            this.dateCounts.url = "api/tags/" + this.attributes.tag._id + "/histogram";
        },
        // fuck you JSON, make up your mind about date formats already.
        parse: function(response) {
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
        width: 1000,
        height: 150,

        createSVG: function() {
            this.linechart = d3.select(this.tagName + '#' + this.id).append('svg')
                .attr('width', this.width)
                .attr('height', this.height);

            this.linechart_x = d3.time.scale()
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
                                         .scale(this.linechart_x)
                                         .orient('bottom');

            this.linechart_y = d3.scale.linear()
                                      .domain([0,
                                               100])
                                      .range([0, this.height]);

            this.linechart_line = d3.svg.line()
                                        .x(function(d) {
                                            return this.linechart_x(d.get('date'));
                                        })
                                        .y(function(d) {
                                            return this.linechart_y(d.get('count'));
                                        });
            this.linechart.append('g')
                          .attr('class', 'axis')
                          .call(linechart_xaxis);
        },

        renderTagLine: function(tagView) {
            tagView.linePath = d3.select(this.tagName + '#' + this.id + ' svg')
                .append('path')
                .attr('class', 'line')
                .style('stroke', tagView.options.color);

            tagView.linePath
            .attr('d', this.linechart_line(tagView.model.dateCounts.models));

        },

        render: function() {
            this.createSVG();
            return this;
        }
    });

    var TagView = Backbone.View.extend({
        tagName: 'li',
        template: _.template("<a style=\"background-color: <%= color %>\" href=\"#\"><%= tag.title %></a>"),
        render: function() {
            this.$el.html(this.template(
                _.extend(this.model.toJSON(),
                         {color: this.options.color})
            ));
            return this;
        }
    });

    var AppView = Backbone.View.extend({
        el: $('#container'),

        initialize: function() {
            var _this = this;
            Tags.fetch().done(function() {
                var lcv = new LineChartView({collection: Tags});
                lcv.render();
                var cscale = d3.scale.category20();
                Tags.each(function(t, i) {
                    t.dateCounts.fetch({reset: true});
                    var v = new TagView({model: t, color: cscale(i)});

                    // render article counts in the linechart when the data
                    // for each tag has finished loading
                    v.listenTo(v.model.dateCounts,
                               'reset',
                               _.bind(function(c) { lcv.renderTagLine(v); }, lcv));
                    $('#tags').append(v.render().el);
                }, _this);
            });
        }

    });

    var App = new AppView;

});
