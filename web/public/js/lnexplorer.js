$(function() {
    if (typeof String.prototype.startsWith != 'function') {
        String.prototype.startsWith = function (str){
            return this.slice(0, str.length) == str;
        };
    }

    var _parseDate = d3.time.format.iso.parse;

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
            this.dateCounts.url = "api/tags/" + encodeURIComponent(this.attributes.tag._id) + "/date_counts";
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
        url: '/api/tags?from=2009-01-01',
    });
    var Tags = new TagList;

    var Entity = Backbone.Model.extend({
        defaults: {
            disabled: false
        },
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
            this.dateCounts.url = "api/entities/" + encodeURIComponent(this.attributes.entity._id) + "/date_counts?from=2011-01-01";
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


    var EntityList = Backbone.Collection.extend({
        model: Entity,
        url: '/api/entities?from=2011-01-01',
    });
    var Entities = new EntityList;

    var LineChartView = Backbone.View.extend({
        tagName: 'div',
        width: 900,
        height: 250,

        createSVG: function() {

            this.linechart = d3.select(this.tagName + '#' + this.id).append('svg')
                .attr('width', '100%')
                .attr('height', '100%')
                .attr('viewBox', '0 0 ' + this.width + ' ' + this.height);

            // filters go in defs element
            var defs = this.linechart.append("defs");

            this.linechart_x = d3.time.scale()
            .domain(d3.extent(_.flatten(this.collection.models.map(function(d) {
                return [d.get('from'), d.get('to')];
            }))))
            .range([0, this.width]);

            var linechart_xaxis = d3.svg.axis()
                                         .scale(this.linechart_x)
                                         .orient('bottom')
                                         .ticks(d3.time.months, 4)
                                         .tickFormat(d3.time.format('%b %Y'))
                                         .tickSize(1);

            console.log(this.collection);
            this.linechart_y = d3.scale.pow()
                                      .exponent(0.6)
                                      .domain([0,
//                                               d3.max(this.collection.models, function(d) { return d.get('count'); })]
                                               90]
                                             )
            //                                      .clamp(true)
                                      .nice()
                                      .range([this.height-20,0]);




            var linechart_yaxis = d3.svg.axis()
                                        .scale(this.linechart_y)
                                        .orient('left')
                                        .tickSize(1)
                                        .ticks(10);

            this.brush = d3.svg.brush()
                               .x(this.linechart_x)
                               .on('brushend',
                                   _.bind(function() {
                                       this.trigger('brush',
                                                    this.brush.extent());
                                   }, this));

            this.linechart_line = d3.svg.line()
                .x(_.bind(function(d) {
                    return this.linechart_x(d.get('date'));
                }, this))
                .y(_.bind(function(d) {
                    return this.linechart_y(d.get('count'));
                }, this));

            this.linechart.append('g')
                          .attr('class', 'axis')
                          .attr('transform', 'translate(0,' + (this.height-20) + ')')
                          .call(linechart_xaxis);

            this.linechart.append('g')
                .attr('class', 'axis')
                .attr('transform', 'translate(20,0)')
                .call(linechart_yaxis);

            this.linechart.append("g")
                          .attr("class", "x brush")
                          .call(this.brush)
                          .selectAll("rect")
                          .attr("y", -6)
                          .attr("height", this.height);
        },

        renderTagLine: function(tagView) {
            tagView.linePath = d3.select(this.tagName + '#' + this.id + ' svg')
                .append('path')
                .datum(tagView.model.dateCounts.models)
                .attr('d', this.linechart_line)
                .attr('id', 'line-' + tagView.$el.attr('id'))
                .attr('class', 'tag-line')
                .style('fill', 'none')
                .style('stroke', tagView.options.color);
            tagView.on('mouseover', _.bind(function(d) {
               $('path[id!=line-'+tagView.$el.attr('id')+'].tag-line', this.$el).css('stroke-opacity', '0.1');
            },this));
            tagView.on('mouseout', _.bind(function(d) {
                $('path[id!=line-'+tagView.$el.attr('id')+'].tag-line', this.$el).css('stroke-opacity', '1');
            }, this));
        },

        render: function() {
//            this.createSVG();
            return this;
        }
    });

    var TagView = Backbone.View.extend({
        tagName: 'li',
        template: _.template("<%= m.tag.title %>"),
        render: function() {
            this.$el.html(this.template({
                m: this.model.toJSON()
            }))
                .css('background-color', this.options.color);
            return this;
        }
    });

    var EntityView = Backbone.View.extend({
        tagName: 'li',
        template: _.template("<img src=\"<%= entity.photo_url.startsWith('http') ? entity.photo_url : 'http://www.lanacion.com.ar' + entity.photo_url %>\"><%= entity.name %>"),
        initialize: function() {
            this.$el.on('mouseover', _.bind(_.partial(this.trigger, 'mouseover'), this));
            this.$el.on('mouseout', _.bind(_.partial(this.trigger, 'mouseout'), this));
        },
        render: function() {
            this.$el.html(this.template(this.model.toJSON()))
                .attr('id', 'entity-' + btoa(this.model.get('entity')._id).replace(/=/g, ''))
                .css('background-color', this.options.color)
                .toggleClass('disabled', this.model.get('disabled'));
            return this;
        }
    });


    var AppView = Backbone.View.extend({
        el: $('#container'),

        initialize: function() {
            var _this = this;

            Entities.fetch({success: function() {
                var cscale = d3.scale.category20();
                var ul = $('#container').prepend('<ul id="entities"></ul>');
                Entities.each(function(t, i) {
                    if (i > 20) t.set('disabled', true);
                    else t.dateCounts.fetch({reset: true});
                    var v = new EntityView({model: t, color: cscale(i)});

                    // render article counts in the linechart when the data
                    // for each tag has finished loading
                    v.listenTo(v.model.dateCounts,
                               'reset',
                               _.bind(function(c) { lcv.renderTagLine(v); }, lcv));

                    $('ul#entities').append(v.render().el);
                }, _this);
                var lcv = new LineChartView({collection: Entities, id: 'entitieslinechart'});
                $('#container').append(lcv.render().el);
                lcv.createSVG();
                lcv.on('brush', function(f) { console.log(f)});
            }});
        }

    });

    var App = new AppView;

});
