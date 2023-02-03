# frozen_string_literal: true

require('facesvg/svg/svg_arc')
require('facesvg/svg/svg_segment')
require('facesvg/svg/vector_n')
require('facesvg/bounds')

module FaceSVG
  extend self

  def edgelist(desc, edges)
    FaceSVG.dbg("#{desc}\n   #{edges.map { |e| [xy(e.start.position), xy(e.end.position)] }}")
  end

  def xy(*args); SVG.vector_2d(*args); end
  def xyz(*args); SVG::VectorN(*args); end

  # A mess of stuff to try to generate some test data
  def part_to_h(part);
    part.methods.include?(:radius) ?
    { start: xyz(part.start.position), end: xyz(part.end.position), radius: part.radius,
      start_angle: part.start_angle, end_angle: part.end_angle,
      center: xyz(part.center), xaxis: xyz(part.xaxis), yaxis: xyz(part.yaxis)
    } :
    { start: xyz(part.start), end: xyz(part.end) };
  end
  def parts_to_json(_parts); edges.map { |p| part_to_h(p) }; end
  def su_part_ary_to_json(su_part_ary); su_part_ary.map { |part| part_to_h(part) }; end

  # @param transformation [Geom::Transformation]
  # @param edge [Sketchup::Edge]
  # @param previous_endxy [Array(Float, Float),nil]
  # @return [FaceSVG::SVG:SVGSegment]
  def createSVGSegment(transformation, edge, previous_endxy)
    startxy = xy(edge.start.position.transform(transformation))
    endxy = xy(edge.end.position.transform(transformation))

    if previous_endxy && ![startxy, endxy].include?(previous_endxy)
      raise "No matching edge #{[startxy, endxy, previous_endxy]}"
    end

    endxy, startxy = startxy, endxy if previous_endxy && previous_endxy == endxy
    FaceSVG.dbg("Defining SVGSegment start, end '%s' '%s'", startxy, endxy)
    SVG::SVGSegment.new(startxy, endxy)
  end

  # @param transformation [Geom::Transformation]
  # @param curve [Sketchup::ArcCurve]
  # @param start_vertex [Sketchup::Vertex]
  # @return [FaceSVG::SVG::SVGArc]
  def createSVGArc(transformation, curve, previous_endxy)
    center = curve.center.transform(transformation)
    centerxy = xy(center)
    start_vertex, end_vertex = end_points(curve)
    startxy = xy(start_vertex.position.transform(transformation))
    endxy = xy(end_vertex.position.transform(transformation))
    xaxis2d = xy(curve.xaxis)
    yaxis2d = xy(curve.yaxis)

    if previous_endxy && ![startxy, endxy].include?(previous_endxy)
      raise "No matching edge #{[startxy, endxy, previous_endxy]}"
    end

    endxy, startxy = startxy, endxy if previous_endxy && previous_endxy == endxy

    radius, start_angle, end_angle = %i[
      radius start_angle end_angle xaxis yaxis
    ].map { |attr| curve.send(attr) }
    FaceSVG.dbg("Defining SVGArc for curve '%s' start, end, center, radius '%s' '%s' '%s' '%s' (ang %s %s)",
                curve.entityID, startxy, endxy, centerxy, radius,
                SVG.to_degrees(start_angle), SVG.to_degrees(end_angle))
    SVG::SVGArc.new(centerxy, curve.radius, startxy, endxy, curve.start_angle, curve.end_angle, xaxis2d, yaxis2d)
  end

  # @param transformation [Geom::Transformation]
  # @param part [Sketchup::ArcCurve, ]
  # @param previous_endxy [Array(Float, Float)]
  # @return [FaceSVG::SVG::SVGArc, FaceSVG::SVG::SVGSegment]
  def createSVGPart(transformation, part, previous_endxy)
    if part.methods.include?(:radius)
      createSVGArc(transformation, part, previous_endxy)
    else
      # Lines and "free hand" curves are just line segments
      createSVGSegment(transformation, part, previous_endxy)
    end
  end

  # Because parts may be connected "end to end" rather than "end to start"
  # flip start and end to have consistent ordering of start and end
  # @param part [Sketchup::Edge, Skecthup::ArcCurve]
  # @return [[Sketchup::Vertex, Sketchup::Vertex]]
  def end_points(part)
    return [part.start, part.end] unless part.methods.include?(:radius)

    first_edge, last_edge = part.first_edge, part.last_edge
    interior_edges = part.edges - [first_edge, last_edge]
    interior_vertices = Set.new(interior_edges.map { |e| [e.start, e.end] }.flatten)

    raise 'Missing start vertex' unless [first_edge.start, first_edge.end].any? { |v| interior_vertices.include?(v) }
    raise 'Missing end vertex' unless [last_edge.start, last_edge.end].any? { |v| interior_vertices.include?(v) }

    start_vertex = interior_vertices.include?(first_edge.end) ? first_edge.start : first_edge.end
    end_vertex = interior_vertices.include?(last_edge.end) ? last_edge.start : last_edge.end

    [start_vertex, end_vertex]
  end

  # Remove all edges that are "part of" the arc curve with entityID "id"
  # @param edges [Array(Sketchup::Edge)]
  # @param id [Integer]
  # @return [nil]
  def remove_associated_curve_edges(edges, id)
    before = edges.size
    edges.reject! { |e| e.curve&.entityID == id }
    FaceSVG.dbg("removed #{before - edges.size} associated with id #{id}")
  end

  # Return an ArcCurve or Edge with its start vertex. When an ArcCurve is returned,
  # all edges associated with the ArcCurve are also removed from the edges array
  # @param edges [Array(Sketchup::Edge)]
  # @param index [Integer]
  # @return [Sketchup::Edge, Sketchup::ArcCurve]
  def extract_curve_or_edge(edges, index)
    edge = edges.slice!(index)
    edgelist("Extracted edge #{index}", [edge])
    curve = edge.curve
    return edge unless curve&.methods&.include?(:radius)

    # The same arc curve is associated with many drawn edges, remove those once processed
    remove_associated_curve_edges(edges, curve.entityID)
    curve
  end

  ################
  # The ordering of edges in sketchup face is arbitrary.  Further an ArcCurve
  # that is a single svg element is associated with multiple Edges.  So this returns only
  # the single ArcCurve, or each Edge when they are line segments not in an ArcCurve,
  # in a predictable order with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
  ################
  # @param loop [Sketchup::Loop]
  # @return [Enumerable<Array([Sketchup::Edge,Sketchup::ArcCurve]>]
  def ordered_su_parts(loop)
    return to_enum(:ordered_su_parts, loop) unless block_given?

    edges = loop.edges.dup()
    edgelist('All edges', edges)
    current_part = extract_curve_or_edge(edges, 0)
    start_vertex, end_vertex = end_points(current_part)
    id = current_part&.entityID; cls = current_part&.class
    FaceSVG.dbg("yield first part #{cls} id #{id} start #{xy(start_vertex.position)} end #{xy(end_vertex.position)}");
    yield current_part

    while (edges.length > 0)
      FaceSVG.dbg("Looping, edges.length #{edges.length}")
      # Find the edge in loop attached to current_edge (or first edge)
      index = edges.find_index { |edge|
        edge.start == end_vertex || edge.end == end_vertex
      }
      # change endpoints to scan all arc_curve edges to get the right end point from start, end
      # Don't calculate is_reversed from edge.end.  Save previous_end_vertex, and compare start_vertex and end_vertex,
      # and switch here if needed.
      unless index
        FaceSVG.dbg("ERROR: Searching for #{xy(end_vertex.position)}")
        edgelist('   searched ', edges)
      end

      current_part = extract_curve_or_edge(edges, index)
      previous_end_vertex = end_vertex
      start_vertex, end_vertex = end_points(current_part)
      start_vertex, end_vertex = [end_vertex, start_vertex] if previous_end_vertex == end_vertex
      id = current_part&.entityID; cls = current_part&.class
      FaceSVG.dbg("yield part #{cls} id #{id} start #{xy(start_vertex.position)} end #{xy(end_vertex.position)}");
      FaceSVG.dbg("   yields, remaining, edges.length #{edges.length}")
      yield current_part
    end
  end

  def get_svgdata_and_bounds(transformation, face)
    # Ensure outer loop is first loop processed
    loops = [face.outer_loop] + face.loops.reject { |x| x == face.outer_loop }

    # Return array of [ [SVGData, Bounds], [SVGData, Bounds] ,...]
    loops.map do |loop|
      su_part_ary = ordered_su_parts(loop).to_a
      svg_parts = FaceSVG.svg_parts_for_su_parts(su_part_ary, transformation)
      # Return array of [SVGData strings, Bounds]
      svgdata = "#{svg_parts.map.with_index { |part, i| part.svgdata(is_first: i == 0) }.join(' ')} Z "
      bounds =  Bounds.new.update(*loop.edges)
      [svgdata, bounds]
    end
  end

  def svg_parts_for_su_parts(parts, transformation)
    # Convert Sketchup Edge and ArcCurves to internal representation
    previous = nil # initial start/end is nominal
    parts.map { |part|
      p = createSVGPart(transformation, part, previous&.endxy)
      previous = p
      p
    }
  end
end
