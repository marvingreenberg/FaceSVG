module FaceSVG
  extend self
  ########################################################################
  # These "elements" collect the edges for an arc with metadata and
  # allow control to reverse orientation, for reordering.  Lines just have an edge
  # Many edges are in one arc, so ignore later edges in a processed arc
  module Reversible
    def inspect
      format('%s %s->%s', self.class.name, startpos, endpos)
    end
    def reverse
      @startpos, @endpos = [@endpos, @startpos]
      self
    end
    attr_reader :is_arc
    attr_reader :startpos
    attr_reader :endpos
  end
  class Arc
    def initialize(edge)
      @startpos = edge.curve.first_edge.start.position
      @endpos = edge.curve.last_edge.end.position
      @is_arc = true
      FaceSVG.dbg('Transform path %s', self)
    end
    include Reversible

    def self.create(curves, edge)
      # return nil if line, or already processed curve containing edge
      return nil if edge.curve.nil? || curves.member?(edge.curve)
      curves << edge.curve
      Arc.new(edge)
    end
  end
  ################
  class Line
    def initialize(edge)
      @startpos = edge.start.position
      @startpos = edge.end.position
      @is_arc = false
      FaceSVG.dbg('Transform path %s', self)
    end
    include Reversible

    def self.create(edge)
      # exit if edge is part of curve
      return nil unless edge.curve.nil?
      Line.new(edge)
    end
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

  def connected(ordered, prev_elt, glob)
    if samepos(prev_elt.endpos, glob.startpos)
      ordered << glob
      true
    elsif samepos(prev_elt.endpos, glob.endpos)
      ordered << glob.reverse
      true
    else
      false
    end
  end

  # Compare two endpoints with tolerance
  TOLERANCE = 0.05
  def samepos(pos1, pos2)
    (pos1 - pos2).length < TOLERANCE
  end
end
