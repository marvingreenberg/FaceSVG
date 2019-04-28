Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/su_util')

module FaceSVG
  module Relief
    extend self

    # Extra clearance to prevent tool evaluating clearance as inaccessible
    RADIUS_CLEARANCE = 0.01
    # When adding relief, need SOME of original edge remaining
    RELIEF_MIN_REMAIN = 0.1

    # Auto symmetric corner relief, only do auto for "small" mortise slots
    # Must have one dimension smaller than AUTO_SYMMETRIC_MAX
    AUTO_SYMMETRIC_MAX = 2.0

    def relieve_corners(selset)
      radius = FaceSVG::cfg().bit_size/2.0
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
      raise format(ERROR_ASYMMETRIC_SINGLE_EDGE_SS, 'face') if CR_ASYMMETRIC == FaceSVG::cfg().corner_relief
      # Not asymmetric, must be symmetric
      # TODO: If only outer loop, relieve outside corners.
      failures = faces.map { |f|
        f.loops.reject(&:outer?).map { |l| symmetric_relief(l, radius, auto: auto) }
      }.count(false)
      raise format(NN_WARNING_LOOPS_IGNORED, failures) if (failures !=0 && !auto)
    end

    def relieve_edge_corners(*edges, radius)
      if CR_ASYMMETRIC == FaceSVG::cfg().corner_relief
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
      raise format(EDGE_TOO_SHORT_NN, radius) if
        edge.length <= (RELIEF_MIN_REMAIN + 4*(radius + RADIUS_CLEARANCE))
    end

    def mid_v(e0, e1)
      m0, m1 = [e0, e1].map { |e|
        e.start.position.to_a.zip(e.end.position.to_a).map { |a, b| (a + b)/ 2.0 }
      }
      (Geom::Point3d.new(m1) - Geom::Point3d.new(m0))
    end

    ############################################################################
    def asymmetric_relief(edge, loop, radius)
      asymmetric_relief_checks(edge, loop, radius)
      # loop becomes invalid during operations
      normal = loop.face.normal
      entities = loop.parent.entities

      radius += RADIUS_CLEARANCE

      # Given selected edge, opposite edge shares no points
      oe0, oe1 = [edge,
                  loop.edges.find { |e|
                    !([edge.start, edge.end].member?(e.start) ||
                      [edge.start, edge.end].member?(e.end))
                  }]
      # Ordering of edges and start,end is unpredictable in SU
      #    p1
      #   (|                 |)
      #    |                 |
      # oe0|-------mid_v---->|oe1
      #    |                 |
      #   (|                 |)
      #    p0
      # p0,p1 are edge ends
      #
      # If things look like this, draw arc (p0,p0+2*r) from 0 to PI
      #   and arc (p1,p1-2*r) from PI to 2*PI.  If things look like this
      # then vector from p1->p0 x midpt_vec is in same direction as face normal
      # or (p0-p1).cross(oe1_mid - oe0_mid).dot( face.normal) > 0
      # If it is negative, just reverse the names p0,p1 and do everything the same
      # By symmetry oe1 can just be renamed oe0 and do everything the same
      # for the other opposite edge

      FaceSVG.dbg('asymmetric_relief edges %s and %s ', oe0, oe1)

      # Have to calculate the mid point vectors ahead since parts of oe0 get deleted
      [[oe0, mid_v(oe0, oe1)],
       [oe1, mid_v(oe1, oe0)]].each do |oe, mvec|
        # Draw two arcs, and delete the waste
        p0, p1 = [oe.start.position, oe.end.position]

        # Swap names if oriented backwards
        p0, p1 = [p1, p0] if (p0 - p1).cross(mvec).dot(normal) < 0

        (r_vec = p1 - p0).length = radius
        xaxis = r_vec.normalize
        # start, center, end
        [[p0, p0 + r_vec, p0 + r_vec + r_vec],
         [p1, p1 - r_vec, p1 - r_vec - r_vec]].each do |s, c, e|
          # make the arc
          arcedges = entities.add_arc(c, xaxis, normal,
                                      radius, 0.0, Math::PI)
          # Delete the one edge (line) that goes from s to e
          waste_edge = arcedges[0].all_connected.grep(Sketchup::Edge).find { |we|
            [s, e].member?(we.start.position) && [s, e].member?(we.end.position)
          }
          entities.erase_entities(waste_edge)
        end
      end
    end
    ############################################################################
    def check_auto_size(v0, v1, auto)
      !auto || v0.length < AUTO_SYMMETRIC_MAX || v1.length < AUTO_SYMMETRIC_MAX
    end
    def check_edge_bigenough(v0, v1, min_edge, radius, auto)
      # If edge is big enough for symmetric relief
      chk = v0.length > min_edge && v1.length > min_edge
      raise format(EDGE_TOO_SHORT_NN, radius) if !chk && !auto
      chk
    end

    def symmetric_relief(loop, radius, auto: false)
      entities = loop.parent.entities
      normal = loop.face.normal
      radius += RADIUS_CLEARANCE
      min_edge = 4 * 0.7071 * radius + RELIEF_MIN_REMAIN

      # For each pair of rectangle corner, draw a relief arc
      waste = rectangle(loop).map { |common, end0, end1|
        v0 = (end0 - common)
        v1 = (end1 - common)
        break [] unless (check_edge_bigenough(v0, v1, min_edge, radius, auto) &&
                         check_auto_size(v0, v1, auto))

        # Two vectors pointing away from common corner, scaled to r * sqrt(1/2)
        # p1
        # .
        # .
        #
        # ^ v1    *c
        # |
        # |
        # |
        # +------> v0 .... p0
        #
        #  If things are as drawn here, with vectors before scaling,
        #  with normal out of screen, draw arc from (common + 2*v1) to
        #  (common + 2*v0).  This means make the xaxis from c-> common + 2*v1
        # But, because the ordering of the edges is
        #  unpredictable, v0 and v1 may be reversed.  Since the face
        #  normal is "up", v0 x v1 in same direction as normal
        #  indicates this is the situation.  If they are reversed (dotprod < 0),
        #  then v0 x v1 is opposite the normal

        # Reverse if normal is opposite
        v0, v1 = [v1, v0] if (v0.cross(v1).dot(normal) < 0)

        v0.length = v1.length = 0.7071 * radius
        # FaceSVG.dbg('*-*-* %s corner v0 %s   v1 %s', common, v0, v1)
        center = common + v0 + v1
        p0 = common + v0 + v0
        p1 = common + v1 + v1
        xaxis = (p1 - center).normalize

        # Make two small offset edges - don't connect arc right to edges
        offset = common - center
        offset.length = 0.02
        # FaceSVG.dbg("*-*-* r= %s  center = %s  xaxis = %s\n\n", radius, center, xaxis)

        e0 = (entities.add_edges  p0, (p0+offset))[0]
        e1 = (entities.add_edges  p1, (p1+offset))[0]
        entities.add_arc(center + offset, xaxis, normal, radius, 0.0, Math::PI)
        # Return corners to allow deletion of corner segments
        [common, e0, e1]
      }
      FaceSVG.dbg('symmetric_relief  %s', waste.empty? ? 'skipped' : 'arcs created')
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
