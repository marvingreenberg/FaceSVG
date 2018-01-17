require 'sketchup'

def pp(cir)
  print "cxy, %0.3f %0.3f %0.3f, r %0.3f,  st ang %0.3f end ang %0.3f xaxis %0.3f %0.3f %0.3f |%0.3f| yaxis  %0.3f %0.3f %0.3f |%0.3f| \n" % (
          cir.center.to_a + [cir.radius, cir.start_angle, cir.end_angle] +
          cir.xaxis.to_a + [cir.xaxis.length] + cir.yaxis.to_a + [cir.yaxis.length] )
end

def am
  Sketchup.active_model
end

def ents
  am.entities
end

def rot(cir, angle)
  pp(cir)
  t = Geom::Transformation.rotation(cir.center, Geom::Vector3d.new(0,0,1), angle)
  ents.transform_entities(t, cir)
  pp(cir)
end

def cir(r)
  es = ents.add_circle([0,0,0],[0,0,1],r)
  c = es[0].curve
  pp(c)
  c
end

def curfac()
  f = am.selection[0]
  f.is_a?(Sketchup::Face) ? f : nil
end

def ej(e)
  "<(%s,%s) (%s,%s)>\n" % [e.start.position[0],e.start.position[1],e.end.position[0],e.end.position[1]].map {|p| p.round(2)}
end

def fe()
  crv = nil
  curfac.edges.each do |e|
    if e.curve.nil?
      print ej(e)
    elsif e.curve != crv
      crv = e.curve
      print ej(crv.first_edge)
      print ej(crv.last_edge)
    end
  end
end
# Solve ellipse  h,k center
# (x - h)^2 / (a^2) + (y-k)^2 / b^2 = 1
# Know two points, the "xaxis" and "yaxis"



def scale(cir, xscale, yscale)
  pp(cir)
  t = Geom::Transformation.scaling(cir.center, xscale, yscale, 1.0)
  e0 = cir.edges[0]
  print "Same circle ? %s \n" % (cir == e0.curve)
  ents.transform_entities(t, cir.edges)
  print "Same circle ? %s \n" % (cir == e0.curve)
  pp(cir) # ? is cir still there?
end

def start(cir)
  pp(cir)
  print "start pos\n"
  e1 = ents.add_edges(cir.center, cir.first_edge.start.position)
  print "end pos\n"
  e2 = ents.add_edges(cir.center, cir.first_edge.end.position)
  e1 + e2
end

def axes(cir)
  cir = selarc if cir.nil?
  pp(cir)
  e1 = ents.add_edges(cir.center, cir.center + cir.xaxis)
  e2 = ents.add_edges(cir.center, cir.center + cir.yaxis)
  e1 + e2
end

def erase(es)
  ents.erase_entities es
end

def selarc()
  ell = am.selection[0].curve
  pp(ell)
  ell
end

def moveorig(ell)
  ell = selarc if ell.nil?
  pp(ell)
  t = Geom::Transformation.translation(ell.center).inverse
  ents.transform_entities(t, ell.edges)
  pp(ell)
end

def unitxform(ell)
  pp(ell)
  
  col1 = ell.xaxis.to_a + [0.0]
  col2 = ell.yaxis.to_a + [0.0]
  col3 = ell.normal.to_a + [0.0]
  col4 = ell.center.to_a + [1.0]
  
  m = Geom::Transformation.new( col1 + col2 + col3 + col4 )

  puts m.to_a
  
  # Unit circle
  edges = ents.add_arc(ORIGIN, X_AXIS, Z_AXIS, 1.0, ell.start_angle, ell.end_angle)
  ents.transform_entities(m, edges)
  ellipse = edges[0].curve

  pp(ellipse)
end
  
def ellipAtAngle(ang, ell)
  cosa = Math::cos(ang)
  sina = Math::sin(ang)
  
  Geom::Vector3d.new( [0,1,2].map { |i|  ell.xaxis[i]*cosa + ell.yaxis[i]*sina } )
end
  
# From https://en.wikipedia.org/wiki/Ellipse#Ellipse_as_an_affine_image_of_the_unit_circle_x%C2%B2+y%C2%B2=1
def vertex(ell)
  ell = selarc if ell.nil?

  if ell.radius == ell.xaxis.length and ell.radius == ell.yaxis.length
    return axes(ell)
  end
  
  f1 = ell.xaxis
  f2 = ell.yaxis
  val = ((f1 % f2) * 2) / ((f1%f1) - (f2%f2))  
  vertex_angle1 = Math::atan(val) / 2
  vertex_angle2 = vertex_angle1 + Math::PI/2
  v1 = ellipAtAngle(vertex_angle1, ell)
  v2 = ellipAtAngle(vertex_angle2, ell)

  e1 = ents.add_edges(ell.center, ell.center + v1)
  e2 = ents.add_edges(ell.center, ell.center + v2)

  puts 'Major Minor %0.4f %0.4f' % [ v1.length, v2.length]

  e1+e2
end
