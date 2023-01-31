# frozen_string_literal: true

require('facesvg/svg/svg_arc')
require('facesvg/svg/svg_segment')
require('facesvg/bounds')

module FaceSVG
  extend self

  def xy(vtx); [vtx.position.x, vtx.position.y]; end

  # @param transformation [Geom::Transformation]
  # @param edge [Sketchup::Edge]
  # @param start_vertex [Sketchup::Vertex]
  # @return [FaceSVG::SVG:SVGSegment]
  def createSVGSegment(transformation, edge, start_vertex)
    raise unless start_vertex == edge.start || start_vertex == edge.end

    s, e = [edge.start, edge.end]
    s, e = [e, s] if start_vertex != s
    startpos = s.position.transform(transformation)
    endpos = e.position.transform(transformation)
    SVG::SVGSegment.new(startpos, endpos)
  end

  # @param transformation [Geom::Transformation]
  # @param edge [Sketchup::Edge]
  # @param start_vertex [Sketchup::Vertex]
  # @return [FaceSVG::SVG::SVGArc]
  def createSVGArc(transformation, edge, start_vertex)
    curve = edge.curve
    raise unless start_vertex == curve.first_edge.start || start_vertex == curve.first_edge.end

    s, e = [curve.first_edge.start, curve.last_edge.end]
    s, e = [e, s] if start_vertex != s
    startpos = s.position.transform(transformation)
    endpos = e.position.transform(transformation)
    center = curve.center.transform(transformation)
    radius, start_angle, end_angle, xaxis, yaxis = %i[
      radius start_angle end_angle xaxis yaxis
    ].map { |attr| curve.send(attr) }
    SVG::SVGArc.new(center, radius, startpos, endpos, start_angle, end_angle, xaxis, yaxis)
  end

  # @param transformation [Geom::Transformation]
  # @param edge [Sketchup::Edge]
  # @param start_vertex [Sketchup::Vertex]
  # @return [FaceSVG::SVG::SVGArc, FaceSVG::SVG::SVGSegment, nil]
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

  ################
  # The ordering of edges in sketchup face boundaries seems
  # arbitrary, make predictable Start at arbitrary element, order
  # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
  ################
  # @param loop [Sketchup::Loop]
  # @return [Enumerable<(Sketchup::Edge,Sketchup::Vertex)>]
  def ordered_edges(loop)
    return to_enum(:ordered_edges, loop) unless block_given?

    edges = loop.edges.dup()
    current_edge = edges.slice!(0)
    start_vertex, end_vertex = current_edge.start, current_edge.end
    FaceSVG.dbg("yield #{[current_edge, 'start', xy(start_vertex), 'end', xy(end_vertex)]}");
    yield [current_edge, start_vertex]

    while (edges.length > 0)
      # Find the edge in loop attached to current_edge (or first edge)
      idx = edges.find_index { |edge|
        FaceSVG.dbg("    end #{xy(end_vertex)} edge start/end #{xy(edge.start)} #{xy(edge.end)}");
        edge.start == end_vertex || edge.end == end_vertex
      }

      current_edge = edges.slice!(idx) # Remove the edge from edges
      start_vertex, end_vertex = current_edge.start == end_vertex ?
        [current_edge.start, current_edge.end] :
        [current_edge.end, current_edge.start]
      FaceSVG.dbg("yield #{[current_edge, 'start', xy(start_vertex), 'end', xy(end_vertex)]}");
      yield [current_edge, start_vertex]
    end
  end

  def get_svgdata_and_bounds(transformation, face)
    # Ensure outer loop is first loop processed
    loops = [face.outer_loop] + face.loops.reject { |x| x == face.outer_loop }

    # Return array of [ [SVGData, Bounds], [SVGData, Bounds] ,...]
    loops.map do |loop|
      svg_parts = FaceSVG.svg_parts_for_loop(loop, transformation)
      # Return array of [SVGData strings, Bounds]
      svgdata = "#{svg_parts.map.with_index { |part, i| part.svgdata(is_first: i == 0) }.join(' ')} Z "
      bounds =  Bounds.new.update(*loop.edges)
      [svgdata, bounds]
    end
  end

  def svg_parts_for_loop(loop, transformation)
    # return loop edges as SVG parts
    ordered_edges(loop).map { |edge, start_vertex|
      createSVGPart(transformation, edge, start_vertex)
    }.compact
  end
end
