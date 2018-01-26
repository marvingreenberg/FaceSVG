###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
load 'shapersvg/svg.rb'

# $uStrings = LanguageHandler.new("shaperSVG")
# extensionSVG = SketchupExtension.new $uStrings.GetString("shaperSVG"), "shapersvg/shapersvg.rb"
# extensionSVG.description=$uStrings.GetString("Create SVG files from faces")
# Sketchup.register_extension extensionSVG, true

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes

# SVG units are: in, cm, mm
INCHES = 'in'
CM = 'cm'
MM = 'mm'

# i = Sketchup::active_model.options['UnitsOptions']['LengthUnit']
# unit = ['in','ft','mm','cm','m'][i]

module ShaperSVG
  module Layout

    SHAPER = 'shaper'
    PROFILEKIND = 'profilekind'
    PK_INNER = 'inner'
    PK_OUTER = 'outer'
    PK_GUIDE = 'guide'

    # format a position with more brevity
    def self.pos_s(p); "(%s,%s,%s)" % p.to_a.map { |m| m.round(2) }; end
    # Sometimes, code to duplicate arc gets end point off by some .01
    #  which screws up key.  So round keys to nearest 0.05

    # Compare two endpoints with tolerance
    TOLERANCE = 0.05
    def self.samepos(pos1, pos2)
      (pos1-pos2).length < TOLERANCE
    end
    
    # The ordering of edges in sketchup face boundaries seems
    # arbitrary, make predictable Start at arbitrary element, order
    # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
    def self.reorder(globs)
      globs = globs.clone

      ordered = [globs[0]]
      globs.delete_at(0)

      while globs.size > 0
        prev_elt = ordered[-1]
        globs.each_with_index do |g,i|
          if ShaperSVG::Layout.samepos(prev_elt.endpos, g.startpos)
            # found next edge, normal end -> start
            ordered << g
            globs.delete_at(i)
            break
          elsif ShaperSVG::Layout.samepos(prev_elt.endpos, g.endpos)
            # reversed edge, end -> end
            ordered << g.reverse
            globs.delete_at(i)
            break
          end
          if i == (globs.size - 1) # at end
            raise "Unexpected: No edge/arc connected %s to at %s" % [prev_elt, ShaperSVG::Layout.pos_s(prev_elt.endpos)]
          end
        end
      end
      ordered
    end

    ########################################################################
    # These "globs" collect the edges for an arc with metadata and control to reverse orientation
    # An edge glob is just a single edge.
    class ArcGlob < Array
      def initialize(elements)
        super()
        self.concat(elements)
      end
      #  Hold the edges that make up an arc as edge array

      def inspect; 'Arc %s->%s%s' % [ShaperSVG::Layout.pos_s(startpos), ShaperSVG::Layout.pos_s(endpos), @reverse ? 'R' : '']; end
      def to_s; inspect; end
      def crv(); self[0].curve; end
      def startpos()
        @reverse ? crv.last_edge.end.position : crv.first_edge.start.position
      end
      def endpos()
        @reverse ? crv.first_edge.start.position : crv.last_edge.end.position
      end
      def reverse(); @reverse = true; self; end
      def isArc(); true; end

      def endpt()
        self[0].curve.edges[-1].end.position
      end
    end

    ########################################################################
    class EdgeGlob < Array
      # Hold a single edge [edge] in fashion analagous to ArcGlob
      def initialize(elements)
        super()
        self.concat(elements)
        @reverse = false
      end
      def inspect; 'Edge %s->%s%s' % [ShaperSVG::Layout.pos_s(startpos), ShaperSVG::Layout.pos_s(endpos), @reverse ? 'R' : '']; end
      def to_s; inspect; end
      def startpos()
        @reverse ? self[0].end.position : self[0].start.position
      end
      def endpos()
        @reverse ? self[0].start.position : self[0].end.position
      end
      # Reverse the ordering reported when asked for start or end
      def reverse(); @reverse = true; self; end
      def isArc(); false; end
      
      def endpt()
        self[0].end.position
      end
    end
    ########################################################################
    class MyEntitiesObserver < Sketchup::EntitiesObserver
      def onElementRemoved(entities, entity_id)
        puts "onElementRemoved: #{entity_id}"
      end
    end    

    # entities.add_observer, remove_observer
    ########################################################################
    class FaceProfile
      def initialize(profilecollection, su_face)
        # Set the transform matrix for all the loops (outer and inside cutouts) on face
        # Transforms the face edge loops onto z=0 plane, to origin (maybe not +xy though?)
        @profilecollection = profilecollection
        @su_face = su_face
        @xform = Geom::Transformation.new(@su_face.bounds.min, @su_face.normal).inverse
        @su_facegrp = @profilecollection.su_profilegrp.entities.add_group()
        @paths = []

        # Keep bounds of transformed face outer profile
        @minx, @miny, @maxx, @maxy = [1e100, 1e100, -1e100,-1e100]
        # Use the outer loop to get the bounds
        # Return array of edge arrays.  If edge array size>1 it is an arc
        glob_arr = self.transform(@su_face.outer_loop.edges, outer: true)
        @paths << glob_arr
        
        puts "Outer %s\n" % [glob_arr]
        # After outerloop is calculated, can layout the whole facegrp
        @profilecollection.layout_facegrp(self, @minx, @miny, @maxx, @maxy)
        
        # For any inner loops, don't recalculate the extents
        @su_face.loops.each do |loop|
          if not loop.equal?(@su_face.outer_loop)
            glob_arr = self.transform(loop.edges, outer: false)
            puts "Inner %s\n" % [glob_arr]
            @paths << glob_arr            
          end
        end
      end

      def createloops()
        @paths.each_with_index.map { |glob_arr,i|
          # First glob arr is the outer profile
          ShaperSVG::SVG::Loop.create(@layout_xf, @minx, @miny, glob_arr, outer: i == 0)
         }
      end

      def su_facegrp()
        @su_facegrp
      end
      
      def id()
        @su_facegrp.guid()
      end

      def layout_xf=(xf)
        @layout_xf = xf
      end
      
      def transform(edges, outer: false)
        curves = [] # curves that have been processed (may edges in same curve)
        # Create yet another group, for each path on the face
        pathgrp = @su_facegrp.entities.add_group()
        # Duplicate the face edges. map returns single edges as [edge] and arcs as [edge,edge,...]
        #  plus nils for subsequent arc edges - this all to maintain the arc metadata
        dupedges = edges.map { |edge| 
          if edge.curve and edge.curve.is_a?(Sketchup::ArcCurve)
            ell_orig = edge.curve
            # FIRST edge in an arc retrieves arc metadata and regenerates ALL arc edges,
            # Subsequent arc edges ignored, returning nil
            if not curves.member?(ell_orig)
              curves << ell_orig
              # Take unit circle, apply ellxform to make duplicate arc...
              # start and end angle are invariant
              elledges = pathgrp.entities.add_arc(
                ORIGIN, X_AXIS, Z_AXIS, 1.0, ell_orig.start_angle, ell_orig.end_angle)
              ellxform = Geom::Transformation.new(
                ell_orig.xaxis.to_a + [0.0] +  ell_orig.yaxis.to_a + [0.0] +
                ell_orig.normal.to_a + [0.0] + ell_orig.center.to_a + [1.0])
              pathgrp.entities.transform_entities(ellxform, elledges)
              ArcGlob.new(elledges)
            else
              nil  # later edges in same ArcCurve
            end
          else
            line_edges = pathgrp.entities.add_edges([edge.start.position, edge.end.position])
            EdgeGlob.new(line_edges)
          end
        }.reject(&:nil?)
        # dupedges is array of LayoutEdge and LayoutArcs
        
        # Transform all edges to z=0 using common face xform (flatten into plain array)
        # Note - may be issues when the original face is in a group, etc...  Multiple transforms
        pathgrp.entities.transform_entities(@xform, dupedges.flatten)
        
        # Find the bounds of the loop after transform
        if outer
          dupedges.flatten.each { |e| 
            x,y = e.start.position[0], e.start.position[1]
            @minx = [x, @minx].min
            @miny = [y, @miny].min
            @maxx = [x, @maxx].max
            @maxy = [y, @maxy].max
          }
        end
        ShaperSVG::Layout.reorder(dupedges)
      end      
    end
    ########################################################################
    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize(title)
        super()
        @title = title
        self.reset()
      end

      ################
      def size()
        @facemap.size
      end
      
      ################
      def reset()
        if @su_profilegrp and @su_profilegrp.valid?
          puts 'Remove %s' % @su_profilegrp
          
          Sketchup::active_model.entities.erase_entities  @su_profilegrp 
        end

        # Use a map to hold the faces, to allow for an observer to update the map
        #  if groups are manually deleted
        @facemap = {}
        @su_profilegrp = nil                      # grp to hold all the SU face groups

        # Information to manage the layout
        @layoutx, @layouty, @rowheight = [0.0, 0.0, 0.0]
        @viewport = [0.0, 0.0, -1e100, -1e100]   # maxx, maxy of viewport updated in layout_facegrp
      end

      # Find a named group  Also active_entities, only entities in open group,etc.
      # model.entities.grep(Sketchup::Group).find_all{|g| g.name==gpname }
      # uses fact that entities is array-like, maybe
      ################
      def su_profilegrp()
        # Return the Sketchup profile group contained in the ProfileGroup instance
        if (not @su_profilegrp) or not @su_profilegrp.valid?
          @su_profilegrp = Sketchup::active_model.entities.add_group()
          @su_profilelayer = Sketchup::active_model.layers.add('SVG Profile')
          @su_profilegrp.layer = @su_profilelayer
          @su_profilegrp.name = 'SVG Profile Group'
        end
        @su_profilegrp
      end
      
      ################
      def add_face_profile(id, fp)
        @facemap[id] = fp
      end
            
      ################
      def write()
        filepath = UI.savepanel(
          "SVG output file", ShaperSVG::Main::default_dir, "%s.svg"%@title)
        if filepath
          ShaperSVG::Main.default_dir = File::dirname(filepath)
          svg = ShaperSVG::SVG::Canvas.new(@viewport, INCHES, ShaperSVG::ADDIN_VERSION)
          svg.title("%s cut profile" % @title)                 
          svg.desc('Shaper cut profile from Sketchup model %s' % @title)
          
          @facemap.values.each do |faceprofile|
            faceprofile.createloops().each do |loop|
              svg.path( loop.svgdata, loop.attributes )
            end
          end
          File.open(filepath,'w') do |file|
            svg.write(file)
          end
        end
      end
      
      # Maybe something like  this is useful
      # edges.each {
      #    |e| e.set_attribute(SHAPER, PROFILEKIND, outer ? PK_OUTER : PK_INNER)
      # }

      def layout_facegrp(faceprofile, minx, miny, maxx, maxy)
        # After the bounds of the outer loop are calculated, transform face layout
        # by moving the group containing the paths (inner and outer)
        facegrp = faceprofile.su_facegrp
        layout_xf = Geom::Transformation.new( [ @layoutx - minx, @layouty - miny, 0.0] )
        @su_profilegrp.entities.transform_entities(layout_xf, facegrp)
        faceprofile.layout_xf = layout_xf
        
        @layoutx += SPACING + maxx - minx
        @viewport[2] = [@viewport[2],@layoutx].max
        # As each element is layed out horizontally, keep track of the tallest bit
        @rowheight = [@rowheight, maxy - miny].max
        if @layoutx > SHEETWIDTH
          @layoutx = 0.0 + SPACING
          @layouty += @rowheight + SPACING
          @rowheight = 0.0
        end
        # Adjust the x, y max for viewport as each face is laid out
        @viewport[3] = [@viewport[3],@layouty+@rowheight].max
        @viewport[2] = [@viewport[2],@layoutx].max

        puts "Layout SU Facegrp #{facegrp} #{minx} #{miny} #{maxx} #{maxy} NEW Layout x,y #{@layoutx},#{@layouty}"

      end

      def process_selection()
        Sketchup.active_model.selection(&:valid?) .each do |elt|
          # TTD Usability improvements?
          if elt.is_a?(Sketchup::Face)
            face = elt
            puts "processing #{face}"
            # Create FaceProfile to hold face profile edges,  holds reference to
            # its containing ProfileCollection
            f = FaceProfile.new(self, face)
            add_face_profile(f.id, f)
          end
        end
      end
    end
  end
end
