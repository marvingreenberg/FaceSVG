Sketchup.require('facesvg/constants')

module FaceSVG
  extend self
  ########################################################################
  # These "elements" collect the edges for an arc with metadata and
  # allow control to reverse orientation, for reordering.  Lines just have an edge
  # Many edges are in one arc, so ignore later edges in a processed arc
  module PathPart
    def reverse
      @startpos, @endpos = [@endpos, @startpos]
      true
    end
    def inspect
      format('%s %s->%s', self.class.name, startpos, endpos)
    end
    def self.create(xform, curves, edge)
      if edge.curve.is_a?(Sketchup::ArcCurve)
        # many edges are part of one arc, process once
        if curves.member?(edge.curve)
          return nil # curve already processed
        end
        curves << edge.curve
        Arc.new(xform, edge)
      else
        # Lines and "free hand" curves are just line segments
        Line.new(xform, edge)
      end
    end
    def connected_vertex?(v)
      # true, if connected.  reverse this PathPart if connected "backwards"
      v == start_vertex || v == end_vertex && reverse()
    end

    attr_reader :start_vertex
    attr_reader :end_vertex

    attr_reader :crv
    attr_reader :xform
    attr_reader :center
    attr_reader :startpos
    attr_reader :endpos
  end

  ################
  class Arc
    def initialize(xform, edge)
      @xform = xform
      @crv = edge.curve
      @start_vertex = @crv.first_edge.start
      @end_vertex = @crv.first_edge.end
      @center = @crv.center.transform(xform)
      @startpos = @start_vertex.position.transform(xform)
      @endpos = @end_vertex.position.transform(xform)
      FaceSVG.dbg('Transform path %s', inspect)
    end
    include PathPart
  end
  ################
  class Line
    def initialize(xform, edge)
      @xform = xform
      @crv = nil
      @start_vertex = edge.start
      @end_vertex = edge.end
      @startpos = @start_vertex.position.transform(xform)
      @endpos = @end_vertex.position.transform(xform)
      FaceSVG.dbg('Transform path %s', inspect)
    end
    include PathPart
  end
  ################
  # The ordering of edges in sketchup face boundaries seems
  # arbitrary, make predictable Start at arbitrary element, order
  # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
  ################
  def reorder(elements)
    # Start at some edge/arc
    ordered = [elements[0]]

    until elements.empty?
      i = elements.index { |e| e.connected_vertex?(ordered[-1].end_vertex) }
      if i.nil?
        raise format(UNEXPECTED_NO_CONNECT_XX_AT_XX,
                     ordered[-1], ordered[-1].end_vertex)
      end
      ordered << elements.delete_at(i)
    end
    ordered
  end
end
