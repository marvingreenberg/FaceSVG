###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
Sketchup.require('facesvg/svg')

# i = Sketchup::active_model.options['UnitsOptions']['LengthUnit']
# unit = ['in','ft','mm','cm','m'][i]

module FaceSVG
  module Layout
    # SVG units are: in, cm, mm... all these are unused for now, except INCHES
    INCHES = 'in'.freeze
    CM = 'cm'.freeze
    MM = 'mm'.freeze
    SHAPER = 'shaper'.freeze
    PROFILEKIND = 'profilekind'.freeze
    PK_INNER = 'inner'.freeze
    PK_OUTER = 'outer'.freeze
    PK_POCKET = 'pocket'.freeze # TTD
    PK_GUIDE = 'guide'.freeze

    # format a position with more brevity
    def self.pos_s(p)
      '(%s,%s,%s)' % p.to_a.map { |m| m.round(2) }
    end
    # Sometimes, code to duplicate arc gets end point off by some .01
    #  which screws up key.  So round keys to nearest 0.05

    # Compare two endpoints with tolerance
    TOLERANCE = 0.05
    def self.samepos(pos1, pos2)
      (pos1 - pos2).length < TOLERANCE
    end

    # The ordering of edges in sketchup face boundaries seems
    # arbitrary, make predictable Start at arbitrary element, order
    # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
    def self.reorder(globs)
      globs = globs.clone

      # Start at some edge/arc
      ordered = [globs[0]]
      globs.delete_at(0)

      until globs.empty?
        prev_elt = ordered[-1]
        globs.each_with_index do |g, i|
          if connected(ordered, prev_elt, g)
            globs.delete_at(i)
            break
          end
          if i == (globs.size - 1) # at end
            raise format('Unexpected: No edge/arc connected %s to at %s',
                         prev_elt, FaceSVG::Layout.pos_s(prev_elt.endpos))
          end
        end
      end
      ordered
    end

    def self.connected(ordered, prev_elt, glob)
      if samepos(prev_elt.endpos, glob.startpos)
        ordered << glob
        true
      elsif samepos(prev_elt.endpos, glob.endpos)
        ordered << glob.reverse
        true
      else
        false
      end
    end
    ########################################################################
    # These "globs" collect the edges for an arc with metadata and
    # control to reverse orientation. An edge glob is just a single edge.
    class ArcGlob < Array
      def initialize(elements)
        super()
        concat(elements)
        # puts 'Transform path %s' % [self]
      end
      #  Hold the edges that make up an arc as edge array

      def inspect
        format('Arc %s->%s%s', FaceSVG::Layout.pos_s(startpos), FaceSVG::Layout.pos_s(endpos), @reverse ? 'R' : '')
      end

      def to_s
        inspect
      end

      def crv
        self[0].curve
      end

      def startpos
        @reverse ? crv.last_edge.end.position : crv.first_edge.start.position
      end

      def endpos
        @reverse ? crv.first_edge.start.position : crv.last_edge.end.position
      end

      def reverse
        @reverse = true
        self
      end

      def isArc
        true
      end
    end

    ########################################################################
    class EdgeGlob < Array
      # Hold a single edge [edge] in fashion analagous to ArcGlob
      def initialize(elements)
        super()
        concat(elements)
        @reverse = false
        # puts 'Transform path %s' % [self]
      end

      def inspect
        format('Edge %s->%s%s', FaceSVG::Layout.pos_s(startpos), FaceSVG::Layout.pos_s(endpos), @reverse ? 'R' : '')
      end

      def to_s
        inspect
      end

      def startpos
        @reverse ? self[0].end.position : self[0].start.position
      end

      def endpos
        @reverse ? self[0].start.position : self[0].end.position
      end

      # Reverse the ordering reported when asked for start or end
      def reverse
        @reverse = true
        self
      end

      def isArc
        false
      end
    end
    ########################################################################
    class MyEntitiesObserver < Sketchup::EntitiesObserver
      def onElementRemoved(_entities, entity_id)
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
        @minx, @miny, @maxx, @maxy = [1e100, 1e100, -1e100, -1e100]
        # Use the outer loop to get the bounds
        # Return array of edge arrays.  If edge array size>1 it is an arc
        glob_arr = transform(@su_face.outer_loop.edges, outer: true)
        @paths << glob_arr

        puts format("Outer %s\n", glob_arr)
        # After outerloop is calculated, can layout the whole facegrp
        @profilecollection.layout_facegrp(self, @minx, @miny, @maxx, @maxy)

        # For any inner loops, don't recalculate the extents
        @su_face.loops.each do |loop|
          next if loop.equal?(@su_face.outer_loop)
          glob_arr = transform(loop.edges, outer: false)
          puts format("Inner %s\n", glob_arr)
          @paths << glob_arr
        end
      end

      def createloops
        @paths.each_with_index.map { |glob_arr, i|
          # First glob arr is the outer profile
          FaceSVG::SVG::Loop.create(@layout_xf, glob_arr, outer: i == 0)
        }
      end

      attr_reader :su_facegrp

      def id
        @su_facegrp.guid
      end

      attr_writer :layout_xf
      def dupcrv(curves, pathgrp, edge)
        return nil unless edge.curve.is_a? Sketchup::ArcCurve
        # FIRST edge in an arc retrieves arc metadata and regenerates ALL arc edges,
        # Subsequent arc edges ignored, only returning nil
        ell_orig = edge.curve
        return nil if curves.member?(ell_orig)
        curves << ell_orig
        # Take unit circle, apply ellxform to make duplicate arc...
        # start and end angle are invariant
        elledges = pathgrp.entities.add_arc(
          ORIGIN, X_AXIS, Z_AXIS, 1.0, ell_orig.start_angle, ell_orig.end_angle
        )
        ellxform = Geom::Transformation.new(
          ell_orig.xaxis.to_a + [0.0] +  ell_orig.yaxis.to_a + [0.0] +
          ell_orig.normal.to_a + [0.0] + ell_orig.center.to_a + [1.0]
        )
        pathgrp.entities.transform_entities(ellxform, elledges)
        ArcGlob.new(elledges)
      end

      def dupedge(pathgrp, edge)
        # exit if edge is part of curve
        return nil if edge.curve.is_a? Sketchup::ArcCurve
        line_edges = pathgrp.entities.add_edges([edge.start.position, edge.end.position])
        EdgeGlob.new(line_edges)
      end

      def updatebounds(dupedges)
        dupedges.flatten.each do |e|
          x = e.start.position[0]
          y = e.start.position[1]
          @minx = [x, @minx].min
          @miny = [y, @miny].min
          @maxx = [x, @maxx].max
          @maxy = [y, @maxy].max
        end
      end

      def transform(edges, outer: false)
        # puts 'Transform path of %s edges' % [edges.size]
        curves = [] # curves that have been processed (many edges in same curve)
        # Create yet another group, for each path on the face
        pathgrp = @su_facegrp.entities.add_group
        # Duplicate the face edges. map returns single edges as
        #  "EdgeGlob" and arcs as ArcGlob (aggregating many edges)
        #  plus nils for subsequent arc edges - this maintains the arc
        #  metadata
        dupedges = edges.map { |edge|
          dupcrv(curves, pathgrp, edge) || dupedge(pathgrp, edge)
        }.reject(&:nil?)
        # dupedges is array of LayoutEdge and LayoutArcs

        # Transform all edges to z=0 using common face xform (flatten into plain array)
        # Note - may be issues when the original face is in a group, etc...  Multiple transforms
        pathgrp.entities.transform_entities(@xform, dupedges.flatten)

        # Find the bounds of the loop after transform
        updatebounds(dupedges) if outer

        # puts 'Reordering %s edges after transform' % [dupedges.flatten.size]
        FaceSVG::Layout.reorder(dupedges)
      end
    end
    ########################################################################
    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize(title)
        super()
        @title = title
        reset()
      end

      def size
        @facemap.size
      end

      def reset
        if @su_profilegrp and @su_profilegrp.valid?
          puts format('Remove %s', @su_profilegrp)
          Sketchup.active_model.start_operation(FaceSVG::LAYOUT_SVG)
          Sketchup.active_model.entities.erase_entities @su_profilegrp
          Sketchup.active_model.commit_operation()
        end

        # Use a map to hold the faces, to allow for an observer to update the map
        #  if groups are manually deleted
        @facemap = {}
        @su_profilegrp = nil # grp to hold all the SU face groups

        # Information to manage the layout
        @layoutx, @layouty, @rowheight = [0.0, 0.0, 0.0]
        @viewport = [0.0, 0.0, -1e100, -1e100] # maxx, maxy of viewport updated in layout_facegrp
      end

      ################
      # Find a named group  Also active_entities, only entities in open group,etc.
      # model.entities.grep(Sketchup::Group).find_all{|g| g.name==gpname }
      # uses fact that entities is array-like, maybe
      ################
      def su_profilegrp
        # Return the Sketchup profile group contained in the ProfileGroup instance
        if (not @su_profilegrp) or not @su_profilegrp.valid?
          @su_profilegrp = Sketchup.active_model.entities.add_group()
          @su_profilelayer = Sketchup.active_model.layers.add('SVG Profile')
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
      def write
        filepath = UI.savepanel(
          'SVG output file', FaceSVG::default_dir, "#{@title}.svg"
        )
        return false if filepath.nil?
        FaceSVG::default_dir = File.dirname(filepath)
        svg = FaceSVG::SVG::Canvas.new(@viewport, INCHES, FaceSVG::version)
        svg.title(format('%s cut profile', @title))
        svg.desc(format('Shaper cut profile from Sketchup model %s', @title))

        @facemap.each_value do |faceprofile|
          faceprofile.createloops().each do |loop|
            svg.path(loop.svgdata, loop.attributes)
          end
        end
        File.open(filepath, 'w') do |file|
          svg.write(file)
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
        layout_xf = Geom::Transformation.new([@layoutx - minx, @layouty - miny, 0.0])
        @su_profilegrp.entities.transform_entities(layout_xf, facegrp)
        faceprofile.layout_xf = layout_xf

        @layoutx += FaceSVG::spacing + maxx - minx
        @viewport[2] = [@viewport[2], @layoutx].max
        # As each element is layed out horizontally, keep track of the tallest bit
        @rowheight = [@rowheight, maxy - miny].max
        if @layoutx > FaceSVG::sheetwidth
          @layoutx = 0.0 + FaceSVG::spacing
          @layouty += @rowheight + FaceSVG::spacing
          @rowheight = 0.0
        end
        # Adjust the x, y max for viewport as each face is laid out
        @viewport[3] = [@viewport[3], @layouty + @rowheight].max
        @viewport[2] = [@viewport[2], @layoutx].max
      end

      def process_selection
        Sketchup.active_model.start_operation(FaceSVG::LAYOUT_SVG)
        Sketchup.active_model.selection(&:valid?) .each do |elt|
          # TTD Usability improvements?
          next unless elt.is_a?(Sketchup::Face)
          face = elt

          # Create FaceProfile to hold face profile edges,  holds reference to
          # its containing ProfileCollection
          f = FaceProfile.new(self, face)
          add_face_profile(f.id, f)
        end
        Sketchup.active_model.commit_operation()
      end
    end
  end
end
