#Sketchup.require('facesvg/constants')

module FaceSVG
  extend self

  def order(e0, e1)
    # Return meeting edges with common start point
    start0,end0 = e0.start.position, e0.end.position
    start1,end1 = e1.start.position, e1.end.position
    common,end0 = [start1,end1].member?(start0) ? [start0,end0] : [end0, start0]
    end1 = (start1==start0) ? end1 : start1
    return [common, end0, end1]
  end

  def rectangular(loop)
    return false if loop.size != 4
    edges = loop.edges.reverse
    corners = edges[0,3].zip(edges[1,3])
    rectangular = corners.map { |e0,e1|
      common, end0, end1 = order(e0, e1)
      Geom::Vector3d.new(end0 - common) % Geom::Vector3d.new(end1 - common)
    }.all?{ |d| d.zero? }
  end

  def symmetric_relief(loop)
    # Only applied to rectangular inner loops, have to have 3 90 deg corners
    return if loop.edges.size != 4
    return unless rectangular(loop)
    # For each pair of edges, draw a relief arc

    edges.zip(edges[1,3]+[edges[0]]).each do |e0,e1|
      common, end0, end1 = order(e0, e1)
      # Two vectors pointing away from common corner, scaled to sqrt(1/2)
      v0 = Geom::Vector3d.new(end0 - common).normalize.length = 0.71
      v1 = Geom::Vector3d.new(end1 - common).normalize.length = 0.71
      center = common + v0 + v1
      radius = 1.0
      normal = v0.cross(v1)
      xaxis = common + v0 - center
      start_angle = 0.0
      end_angle = 100.0.degrees
      Sketchup.active_model.entities.add_arc(center, xaxis, normal, radius, start_angle, end_angle)
    end
  end
end

def relief
  f = Sketchup::active_model.selection[0]
  (f.loops - [f.outer_loop]).each do |l|
    FaceSVG.symmetric_relief(l)
  end
end
