Sketchup.require('facesvg/su_util')

module FaceSVG
  extend self
  ########################################################################
  # These "elements" collect the edges for an arc with metadata and
  # allow control to reverse orientation, for reordering.  Lines just have an edge
  # Many edges are in one arc, so ignore later edges in a processed arc
  module PathPart
    def reverse
      @startpos, @endpos = [@endpos, @startpos]
      self
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
    attr_reader :crv
    attr_reader :xform
    attr_reader :center
    attr_reader :startpos
    attr_reader :endpos
  end
  class Arc
    def initialize(xform, edge)
      @xform = xform
      @crv = edge.curve
      @center = @crv.center.transform(xform)
      @startpos = @crv.first_edge.start.position.transform(xform)
      @endpos = @crv.last_edge.end.position.transform(xform)
      FaceSVG.dbg('Transform path %s', inspect)
    end
    include PathPart
  end
  ################
  class Line
    def initialize(xform, edge)
      @xform = xform
      @crv = nil
      @startpos = edge.start.position.transform(xform)
      @endpos = edge.end.position.transform(xform)
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
    elements.delete_at(0)

    until elements.empty?
      prev_elt = ordered[-1]
      elements.each_with_index do |g, i|
        if connected(ordered, prev_elt, g)
          elements.delete_at(i)
          break
        end
        if i == (elements.size - 1) # at end
          raise format('Unexpected: No edge/arc connected %s at %s',
                       prev_elt, prev_elt.endpos)
        end
      end
    end
    ordered
  end

  def connected(ordered, prev_elt, pathpart)
    if samepos(prev_elt.endpos, pathpart.startpos)
      ordered << pathpart
      true
    elsif samepos(prev_elt.endpos, pathpart.endpos)
      ordered << pathpart.reverse
      true
    else
      false
    end
  end
end
