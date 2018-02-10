###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/su_util')
Sketchup.require('facesvg/svg')

module FaceSVG
  module Layout
    # The ordering of edges in sketchup face boundaries seems
    # arbitrary, make predictable Start at arbitrary element, order
    # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
    def self.reorder(elements)
      # Start at some edge/arc
      ordered = [elements[0]]
      elements.delete_at(0)

      until elements.empty?
        prev_elt = ordered[-1]
        elements.each_with_index do |g, i|
          if connected(ordered, prev_elt, g)
            elements.delete_at(i)
            break
          end
          if i == (elements.size - 1) # at end
            raise format('Unexpected: No edge/arc connected %s to at %s',
                         prev_elt, FaceSVG.pos_s(prev_elt.endpos))
          end
        end
      end
      ordered
    end

    def self.connected(ordered, prev_elt, glob)
      if FaceSVG.samepos(prev_elt.endpos, glob.startpos)
        ordered << glob
        true
      elsif FaceSVG.samepos(prev_elt.endpos, glob.endpos)
        ordered << glob.reverse
        true
      else
        false
      end
    end

    ########################################################################
    # These "elements" collect the edges for an arc with metadata and
    # control to reverse orientation.  Lines just have an edge
    # Many edges are in one arc, so ignore later edges in a processed arc
    module Reversible
      def inspect
        format('%s %s->%s', self.class.name, FaceSVG.pos_s(startpos), FaceSVG.pos_s(endpos))
      end
      def reverse
        @startpos, @endpos = [@endpos, @startpos]
        self
      end
      attr_reader :is_arc
      attr_reader :startpos
      attr_reader :endpos
    end
    class Arc
      def initialize(edge)
        @startpos = edge.curve.first_edge.start.position
        @endpos = edge.curve.last_edge.end.position
        @is_arc = true
        FaceSVG.dbg('Transform path %s', self)
      end
      include Reversible

      def self.make(curves, edge)
        # return nil if line, or already processed curve containing edge
        return nil if edge.curve.nil? || curves.member?(edge.curve)
        curves << edge.curve
        Arc.new(edge)
      end
    end
    ################
    class Line
      def initialize(edge)
        @startpos = edge.start.position
        @startpos = edge.end.position
        @is_arc = false
        FaceSVG.dbg('Transform path %s', self)
      end
      include Reversible

      def self.make(edge)
        # exit if edge is part of curve
        return nil unless edge.curve.nil?
        Line.new(edge)
      end
    end

    ################
    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize(title)
        @title = title
        reset()
      end
      ################
      # TODO: Use a map to hold the faces??,
      #   to allow for an observer to update the layout if elements are deleted
      def reset
        # UI: reset the layout state and clear any existing profile group
        if su_profilegrp(create: false)
          FaceSVG.dbg('Remove %s', @su_profilegrp)
          Sketchup.active_model.entities.erase_entities @su_profilegrp
        end

        @su_profilegrp = nil # grp to hold all the SU face groups

        # Information to manage the layout, maxx, maxy updated in layout_facegrp
        @layoutx, @layouty, @rowheight = [CFG.layout_spacing, CFG.layout_spacing, 0.0]
        @viewport = [0.0, 0.0, -1e100, -1e100]
      end

      ################
      def write
        # UI: write any layed out profiles as svg
        # TODO: Figure out multi file
        filepath = UI.savepanel(SVG_OUTPUT_FILE,
                                CFG.default_dir, "#{@title}.svg")
        return false if filepath.nil?
        CFG.default_dir = File.dirname(filepath)
        svg = SVG::Canvas.new(@viewport, INCHES, CFG.facesvg_version)
        svg.title(format('%s cut profile', @title))
        svg.desc(format('Shaper cut profile from Sketchup model %s', @title))

        su_profilegrp.entities.grep(Sketchup::Group).each do |g|
          # Get a surface (to calculate pocket offset if needed)
          faces = g.entities.grep(Sketchup::Face)
          surface = faces.find(&marked?(SURFACE))
          faces.each { |f| svgpaths(svg, f, surface) }
        end
        # TODO: Figure out multi file
        if CFG.svg_output == SINGLE_FILE
          File.open(filepath, 'w') { |file| svg.write(file) }
        else
          UI.messagebox('Not implemented')
        end
      end
      ################
      def process_selection
        # UI: process any selected faces and lay out into profile grp
        layout_facegrps(*Sketchup.active_model.selection(&:valid?).grep(Sketchup::Face))
      end

      ################
      def su_profilegrp(create: true)
        # Find or create the group for the profile entities
        return @su_profilegrp if @su_profilegrp && @su_profilegrp.valid?
        @su_profilegrp = Sketchup::active_model.entities.grep(Sketchup::Group)
                                 .find { |g| g.name==PROFILE_GROUP && g.valid? }
        return @su_profilegrp if @su_profilegrp
        # None existing, create (unless flag false)
        return nil unless create
        @su_profilegrp = Sketchup.active_model.entities.add_group()
      end
      ################
      def empty?
        su_profilegrp(create: false).nil?
      end
      ################
      def add_su_facegrp(facegrp)
        # Add new element to existing profile group by recreating the group
        @su_profilegrp = Sketchup.active_model.entities
                                 .add_group(su_profilegrp.explode + [facegrp])
        @su_profilelayer = Sketchup.active_model.layers.add(PROFILE_LAYER)
        @su_profilegrp.layer = @su_profilelayer
        @su_profilegrp.name = PROFILE_GROUP
      end
      ################
      def layout_facegrps(*su_faces)
        FaceSVG.capture_faceprofiles(*su_faces) do |newgrp|
          bounds = newgrp.bounds
          minx, miny = bounds.min.x, bounds.min.y
          maxx, maxy = bounds.max.x, bounds.max.y

          FaceSVG.dbg('Face bounds,  %s %s to %s,%s,0',
                      bounds.min, bounds.max, @layoutx, @layoutx)
          add_su_facegrp(newgrp)

          layout_xf = Geom::Transformation
                      .new([@layoutx - minx, @layouty - miny, 0.0])
          su_profilegrp.entities.transform_entities(layout_xf, newgrp)

          @layoutx += CFG.layout_spacing + maxx - minx
          @viewport[2] = [@viewport[2], @layoutx].max
          # As each element is layed out horizontally, keep track of the tallest bit
          @rowheight = [@rowheight, maxy - miny].max
          if @layoutx > CFG.layout_width
            @layoutx = 0.0 + CFG.layout_spacing
            @layouty += @rowheight + CFG.layout_spacing
            @rowheight = 0.0
          end
          # Adjust the x, y max for viewport as each face is laid out
          @viewport[3] = [@viewport[3], @layouty + @rowheight].max
          @viewport[2] = [@viewport[2], @layoutx].max
        end
      end

      ################

      def svgpaths(svg, face, surface)
        # Only do outer loop for pocket faces
        if marked?(POCKET).call(face)
          paths = [face.outer_loop]
          depth = face_offset(face, surface)
          profile_kind = PK_POCKET
        else
          profile_kind = nil # set for each loop on face
          paths = face.loops
          depth = CFG.cut_depth
        end

        paths.each do |loop|
          profile_kind = profile_kind || (loop == face.outer_loop) ? PK_OUTER : PK_INNER
          FaceSVG.dbg('Profile, %s edges, %s %s', loop.edges.size, profile_kind, depth)
          # regroup edges so arc edges are grouped with metadata, all ordered end to start
          curves = [] # Keep track of processed arcs
          pathparts = loop.edges.map { |edge|
            Arc.create(curves, edge) || Line.create(edge)
          }.reject(&:nil?)
          pathparts = Layout.reorder(pathparts)
          svgloop = SVG::Loop.create(pathparts, profile_kind, depth)
          svg.path(svgloop.svgdata, svgloop.attributes)
        end
      end
    end
  end
end
