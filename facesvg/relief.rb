#Sketchup.require('facesvg/constants')

begin
  Object.send(:remove_const, :FaceSVG)
rescue
end

module FaceSVG
  extend self

  def order(ep0, ep1)
    # Return four meeting edges with common start point
    start0,end0 = ep0
    start1,end1 = ep1
    common,end0 = [start1,end1].member?(start0) ? [start0,end0] : [end0, start0]
    end1 = (start1==common) ? end1 : start1
    [ common, end0, end1 ]
  end

  def rectangle(loop)
    # Return four corners (common) with connected points
    # Return empty array if it isn't a rectangle (corner not right angle)
    return [] if loop.edges.size != 4
    # Read the data OUT of edges, since loop can change during iteration
    #  because of geometry changes
    edgepoints = loop.edges.map { |e| [e.start.position, e.end.position] }
    # Make sure three corners are 90 degrees
    corners = edgepoints.zip(edgepoints.rotate(1))

    rect = corners.map { |e0,e1|
      common, end0, end1 = order(e0, e1)
      dotprod = (end0 - common) % (end1 - common)
      break unless dotprod < 0.001
      [common, end0, end1]
    }
    rect.nil? ? [] : rect
  end

  def auto_asymmetric_relief(loop)
  end

  def asymmetric_relief(edge, face: nil)
    radius = 0.125 + 0.01

    current_model = edge.model
    if face.nil?
      faces = edge.faces
      # Find a face with this edge as an inner loop, can only be one
      face = faces.find { |f|
        f.loops.reject { |l| l.outer? }.any? { |l| l.edges.member? (edge) }
      }
      if face.nil?
        UI.messagebox('Edge not part of an inner loop, cannot generate corner relief ')
        return
      end
    end

    if edge.length <= 2*radius
      UI.messagebox('Cannot generate corner relief with radius %s - edge too short' % radius)
      return
    end

    # Draw two loops, and delete the waste
    p0 = edge.start.position
    p1 = edge.end.position
    [[p0,p1], [p1,p0]].each do |s,e|
      r_vec = e-s
      r_vec.length = radius
      xaxis = (e-s).normalize
      center = s + r_vec

      arcedges = current_model.entities.add_arc(center, xaxis, face.normal, radius, 0.0, -Math::PI)
      waste_ends = [s, center+r_vec]
      waste_edge = arcedges[0]
        .all_connected.grep(Sketchup::Edge).find { |e|
        waste_ends.member?(e.start.position) && waste_ends.member?(e.end.position)
      }
      current_model.entities.erase_entities(waste_edge)
    end
  end

  # TODO: bug, with component, the current_model is apparently wrong -
  #   creating the arcs in a different model.entities somehow.
  def symmetric_relief(loop)
    # For each pair of edges, draw a relief arc
    radius = 0.125 + 0.01

    current_model = loop.model

    waste = rectangle(loop).map { |common, end0, end1|
      # Two vectors pointing away from common corner, scaled to sqrt(1/2)
      v0 = (end0 - common)
      v1 = (end1 - common)
      v0.length = v1.length = 0.7071 * radius
      puts format("*-*-* %s corner v0 %s   v1 %s", common, v0, v1)
      center = common + v0 + v1
      normal = v0.cross(v1)
      p0 = common + v0 + v0
      p1 = common + v1 + v1
      xaxis = (p0 - center).normalize

      # Make a small offset
      offset = common - center
      offset.length = 0.02
      puts format("** r= %s  center = %s  xaxis = %s\n\n", radius, center, xaxis)

      start_angle = 0.0
      end_angle = -Math::PI
      e0 = (current_model.entities.add_edges  p0, (p0+offset))[0]
      e1 = (current_model.entities.add_edges  p1, (p1+offset))[0]
      current_model.entities.add_arc(center + offset, xaxis, normal, radius, start_angle, end_angle)
      # Return corners to allow deletion of corner segments
      [common, e0, e1]
    }
    # After the reliefs are drawn the waste edges must be deleted
    #  These are the edges connected to the offset edges, with one end at the common corner

    waste.each do |common, e0, e1|
      waste_edges = (e1.all_connected + e0.all_connected).grep(Sketchup::Edge)
        .select { |e| e.start.position == common ||  e.end.position == common }
      current_model.entities.erase_entities(waste_edges)
    end
  end
end

def a_relief
  e = Sketchup::active_model.selection[0]

  FaceSVG.asymmetric_relief(e)
end


def relief
  f = Sketchup::active_model.selection[0]
  (f.loops - [f.outer_loop]).each do |l|
    FaceSVG.symmetric_relief(l)
  end
end
