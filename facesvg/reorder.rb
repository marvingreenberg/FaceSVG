Sketchup.require('facesvg/constants')

module FaceSVG
  extend self
  ########################################################################
  # These "elements" collect the edges for an arc with metadata. Lines
  # just have an edge.  Many edges are in one arc, so ignore later edges
  # in a processed arc
  module PathPart
    def inspect
      format('%s %s->%s', self.class.name, startpos, endpos)
    end
    def self.create(xform, edge, start_vertex)
      if edge.curve.is_a?(Sketchup::ArcCurve) && !edge.curve.is_polygon?
        # many edges are part of one arc, process once, when its the start edge
        # or the confused end_edge (but definitely only once)
        #   else return nil
        Arc.new(xform, edge, start_vertex) if
          [edge.curve.first_edge.start, edge.curve.last_edge.end].member?(start_vertex)
      else
        # Lines and "free hand" curves are just line segments
        Line.new(xform, edge, start_vertex)
      end
    end
    attr_reader :crv
    attr_reader :center
    attr_reader :startpos
    attr_reader :endpos
  end

  ################
  class Arc
    def initialize(xform, edge, start_vertex)
      @crv = edge.curve
      s, e = [@crv.first_edge.start, @crv.last_edge.end]
      s, e = [e, s] if start_vertex != s
      @startpos = s.position.transform(xform)
      @endpos = e.position.transform(xform)
      @center = @crv.center.transform(xform)
      FaceSVG.dbg('Transform path %s (s %s e %s start %s)', inspect, s.position, e.position, start_vertex.position)
    end
    include PathPart
  end
  ################
  class Line
    def initialize(xform, edge, start_vertex)
      @crv = nil
      s, e = [edge.start, edge.end]
      s, e = [e, s] if start_vertex != s
      @startpos = s.position.transform(xform)
      @endpos = e.position.transform(xform)
      FaceSVG.dbg('Transform path %s (s %s e %s start %s)', inspect, s.position, e.position, start_vertex.position)
    end
    include PathPart
  end
  ################
  # The ordering of edges in sketchup face boundaries seems
  # arbitrary, make predictable Start at arbitrary element, order
  # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
  ################
  def ordered_edges(loop)
    # Yields each edge and its end vertex (end for the given ordering)
    # Sketchup does not guarantee edges are in order, or that start matches end.
    return to_enum(:ordered_edges, loop) unless block_given?

    first = loop.edges[0]
    curredge, currstart, currend = [first, first.start, first.end]
    # just use number of edges to count number to yield
    yield [curredge, currstart] # Yield first, then yield remaining size-1
    (1..(loop.edges.size-1)).each do
      # from the edges connected to endof(curredge)
      #  find the edge that is NOT curredge but IS in the loop
      # If only two edges on vertex (usual) OTHER Must be on loop, skip extra check
      connected = currend.edges.reject { |e| e == curredge }
      nextedge = (connected.size == 1 ? connected[0]
        : connected.find { |ce| loop.edges.member?(ce) })
      nextstart, nextend = [nextedge.end, nextedge.start]
      nextstart, nextend = [nextend, nextstart] if currend == nextend
      curredge, currstart, currend = [nextedge, nextstart, nextend]
      yield [curredge, currstart]
    end
  end

  def reordered_path_parts(loop, xf)
    # return loop edges so arc edges are grouped with metadata, all ordered end to start
    ordered_edges(loop).map { |edge, start_vertex|
      PathPart.create(xf, edge, start_vertex)
    }.reject(&:nil?)
  end
end
