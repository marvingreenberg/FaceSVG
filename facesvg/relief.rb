Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/su_util')

module FaceSVG
  module Relief
    extend self

    # Extra clearance to prevent tool evaluating clearrance as inaccessible
    RADIUS_CLEARANCE = 0.01

    # Auto symmetric corner relief, only do auto for "small" mortise slots
    # Must have one dimension smaller than AUTO_SYMMETRIC_MAX
    AUTO_SYMMETRIC_MAX = 2.5

    def cw(loop, edge: nil)
      # Return true if the loop edges are returned in a clockwise direction
      # Note taht teh sense of cw or ccw may be incorrect, but is returning
      # a value which gives correct results below to correct for sketchup ordering
      # variations of edges.
      edge = loop.edges[0] if edge.nil?
      connected = loop.edges.find { |e|
        e != edge && [e.start.position, e.end.position].member?(edge.start.position)
      }
      edge_v, connected_v = corner_vectors(edge, connected)
      edge_v.cross(connected_v).dot(loop.face.normal) > 0
    end

    def relieve_corners(selset)
      radius = CFG.bit_diameter/2.0
      # There may be faces selected, or edges
      faces = selset.grep(Sketchup::Face)
      if faces.empty?
        relieve_edge_corners(*selset.grep(Sketchup::Edge), radius)
      else
        relieve_face_corners(*faces, radius)
      end
    rescue RuntimeError => msg
      UI.messagebox(msg)
    end

    def relieve_face_corners(*faces, radius, auto: false)
      raise format(ERROR_ASYMMETRIC_SINGLE_EDGE_SS, 'face') if CR_ASYMMETRIC == CFG.corner_relief
      # Not asymmetric, must be symmetric
      # TODO: If only outer loop, relieve outside corners.
      failures = faces.map { |f|
        f.loops.reject(&:outer?).map { |l| symmetric_relief(l, radius, auto: auto) }
      }.count(false)
      raise format(NN_WARNING_LOOPS_IGNORED, failures) if (failures !=0 && !auto)
    end

    def relieve_edge_corners(*edges, radius)
      if CR_ASYMMETRIC == CFG.corner_relief
        raise format(ERROR_ASYMMETRIC_SINGLE_EDGE_SS, edges.size) if edges.size != 1
        asymmetric_relief(edges[0], inner_loop_with(edges[0]), radius)
      else
        # Symmetric for an edge just finds the loop containing the edge
        loops = edges.map { |e| inner_loop_with(e, warning: false) }.reject(&:nil?).uniq
        loops.each { |l| symmetric_relief(l, radius) }
      end
    end

    def inner_loop_with(edge, warning: true)
      faces = edge.faces
      # Find an inner loop containing this edge, can only be one
      loop = faces.map(&:loops).flatten.reject(&:outer?)
                  .find { |l| l.edges.member?(edge) }
      raise EDGE_NOT_INNER if loop.nil? && warning
      loop
    end

    def corner_vectors(edge, connected)
      ep0 = [edge.start.position, edge.end.position]
      ep1 = [connected.start.position, connected.end.position]
      common_p, edge_p, connected_p = corner(ep0, ep1)
      # get two corner vectors
      [edge_p - common_p, connected_p - common_p]
    end

    def corner(ep0, ep1)
      start0, end0 = ep0
      start1, end1 = ep1
      common, end0 = [start1, end1].member?(start0) ? [start0, end0] : [end0, start0]
      end1 = (start1==common) ? end1 : start1
      [common, end0, end1]
    end

    def rectangle(loop)
      # Return four corners (common) with connected points
      # Return empty array if it isn't a rectangle (corner not right angle)
      return [] if loop.edges.size != 4
      # get corners for each pair of edges
      edgepoints = loop.edges.map { |e| [e.start.position, e.end.position] }
      corners = edgepoints.zip(edgepoints.rotate(1)).map { |e0, e1| corner(e0, e1) }

      # Return a rect of 4 triples
      corners.map { |common, end0, end1|
        # Check 90 degree corners
        break [] unless (end0 - common).dot(end1 - common) < 0.001
        [common, end0, end1]
      }
    end

    def asymmetric_relief_checks(edge, loop, radius)
      raise EDGE_NOT_IN_RECTANGLE if loop.edges.size != 4
      raise EDGE_NOT_INNER if loop.outer?
      raise format(EDGE_TOO_SHORT_NN, radius) if edge.length <= 2*(radius + 2*RADIUS_CLEARANCE)
    end
    ############################################################################
    def asymmetric_relief(edge, loop, radius)
      asymmetric_relief_checks(edge, loop, radius)
      # if the normal in same direction as face normal, clockwise loop
      cw_fl = cw(loop, edge: edge)

      radius += RADIUS_CLEARANCE

      opposite_edges = [edge,
                        loop.edges.find { |e|
                          !([edge.start, edge.end].member?(e.start) ||
                          [edge.start, edge.end].member?(e.end))
                        }]

      FaceSVG.dbg('asymmetric_relief %s, %s edges', cw_fl ? 'cw' : 'ccw', opposite_edges)

      opposite_edges.each do |oe|
        # Draw two arcs, and delete the waste
        p0 = oe.start.position
        p1 = oe.end.position
        [[p0, p1, true], [p1, p0, false]].each do |st, en, dxn_fl|
          r_vec = en-st
          r_vec.length = radius
          xaxis = r_vec.normalize
          xaxis.reverse! unless (dxn_fl ^ cw_fl)
          center = st + r_vec
          entities = loop.parent.entities
          arcedges = entities.add_arc(center, xaxis, loop.face.normal, radius, 0.0, Math::PI)
          waste_ends = [st, center+r_vec]
          waste_edge = arcedges[0].all_connected.grep(Sketchup::Edge).find { |we|
            waste_ends.member?(we.start.position) && waste_ends.member?(we.end.position)
          }
          entities.erase_entities(waste_edge)
        end
      end
    end
    ############################################################################
    def check_auto_size(v0, v1, auto)
      !auto || v0.length < AUTO_SYMMETRIC_MAX || v1.length < AUTO_SYMMETRIC_MAX
    end
    def check_edge_bigenough(v0, v1, min_edge)
      # If edge is big enough for symmetric relief
      v0.length > min_edge && v1.length > min_edge
    end

    def symmetric_relief(loop, radius, auto: false)
      entities = loop.parent.entities
      cw_fl = cw(loop)
      radius += RADIUS_CLEARANCE
      min_edge = 4 * 0.7071 * radius
      # For each pair of rectangle corner, draw a relief arc
      waste = rectangle(loop).map { |common, end0, end1|
        # Two vectors pointing away from common corner, scaled to sqrt(1/2)
        v0 = (end0 - common)
        v1 = (end1 - common)
        break [] unless check_edge_bigenough(v0, v1, min_edge) && check_auto_size(v0, v1, auto)

        v0.length = v1.length = 0.7071 * radius
        # FaceSVG.dbg('*-*-* %s corner v0 %s   v1 %s', common, v0, v1)
        center = common + v0 + v1
        p0 = common + v0 + v0
        p1 = common + v1 + v1
        xaxis = (p0 - center).normalize
        xaxis.reverse! unless cw_fl

        # Make a small offset
        offset = common - center
        offset.length = 0.02
        # FaceSVG.dbg("*-*-* r= %s  center = %s  xaxis = %s\n\n", radius, center, xaxis)

        e0 = (entities.add_edges  p0, (p0+offset))[0]
        e1 = (entities.add_edges  p1, (p1+offset))[0]
        entities.add_arc(center + offset, xaxis, loop.face.normal, radius, 0.0, Math::PI)
        # Return corners to allow deletion of corner segments
        [common, e0, e1]
      }
      FaceSVG.dbg('symmetric_relief  %s edges: %s', loop.edges.size, waste.empty? ? 'skipped' : 'arcs created')
      # After the reliefs are drawn the waste edges must be deleted
      #  These are the edges connected to the offset edges, with one end at the common corner

      waste.each do |common, e0, e1|
        waste_edges = (e1.all_connected + e0.all_connected)
                      .grep(Sketchup::Edge)
                      .select { |e| e.start.position == common || e.end.position == common }
        entities.erase_entities(waste_edges)
      end

      # If waste was empty, it was an error (not rectangular).  true was success
      !waste.empty?
    end
  end
end
