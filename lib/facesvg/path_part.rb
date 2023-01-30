# frozen_string_literal: true

require('facesvg/svg/svg_arc')
require('facesvg/svg/svg_segment')

module FaceSVG
  extend self

  module PathPart
    extend self

    def createSVGSegment(transformation, edge, start_vertex)
      s, e = [edge.start, edge.end]
      s, e = [e, s] if start_vertex != s
      startpos = s.position.transform(transformation)
      endpos = e.position.transform(transformation)
      SVGSegment.new(startpos, endpos)
    end

    def createSVGArc(transformation, edge, start_vertex)
      curve = edge.curve
      s, e = [curve.first_edge.start, curve.last_edge.end]
      s, e = [e, s] if start_vertex != s
      startpos = s.position.transform(transformation)
      endpos = e.position.transform(transformation)
      center = curve.center.transform(transformation)
      radius, start_angle, end_angle, xaxis, yaxis = %i[
        radius start_angle end_angle xaxis yaxis
      ].map { |attr| curve.send(attr) }
      SVGArc.new(center, radius, startpos, endpos, start_angle, end_angle, xaxis, yaxis)
    end

    def createSVGPart(transformation, edge, start_vertex)
      if edge.curve.is_a?(Sketchup::ArcCurve) && !edge.curve.is_polygon?
        # many edges are part of one arc, process once, when its the start edge
        # or the confused end_edge (but definitely only once)
        #   else return nil
        createSVGArc(transformation, edge, start_vertex) if
          [edge.curve.first_edge.start, edge.curve.last_edge.end].member?(start_vertex)
      else
        # Lines and "free hand" curves are just line segments
        createSVGSegment(transformation, edge, start_vertex)
      end
    end
    attr_reader :crv, :center, :startpos, :endpos
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

  def svg_parts_for_loop(loop, transformation)
    # return loop edges as SVG parts
    ordered_edges(loop).map { |edge, start_vertex|
      PathPart.createSVGPart(transformation, edge, start_vertex)
    }.compact
  end
end
