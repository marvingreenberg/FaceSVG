# frozen_string_literal: true

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
    ################
    extend self

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
        FaceSVG.su_close_active()
        if su_profilegrp(create: false)
          FaceSVG.dbg('Remove %s', @su_profilegrp)
          Sketchup.active_model.entities.erase_entities @su_profilegrp
        end

        @su_profilegrp = nil # grp to hold all the SU face groups

        # Information to manage the layout, maxx, maxy updated in layout_facegrp
        @layoutx, @layouty, @rowheight = [CFG.layout_spacing, CFG.layout_spacing, 0.0]
      end

      ################
      def makesvg(name, *grps)
        bnds = Bounds.new.update(*grps)
        viewport = [bnds.min.x, bnds.min.y, bnds.max.x, bnds.max.y]
        svg = SVG::Canvas.new(name, viewport, CFG.units)
        svg.title(format('%s cut profile', @title))
        svg.desc(format('Shaper cut profile from Sketchup model %s', @title))

        grps.each do |g|
          # Get a surface (to calculate pocket offset if needed)
          faces = g.entities.grep(Sketchup::Face)
          surface = faces.find { |face| face.material == FaceSVG.surface }
          # Use tranform if index nil? - means all svg in one file, SINGLE_FILE
          faces.each { |face| svg.add_paths(g.transformation, face, surface) }
        end
        svg
      end
      ################
      def write
        # UI: write any layed out profiles as svg
        grps = su_profilegrp.entities.grep(Sketchup::Group)

        # single_file - generate one "svg::Canvas" with all face grps
        outpath = UI.savepanel(SVG_OUTPUT_FILE,
                               CFG.default_dir, "#{@title}.svg")
        return false if outpath.nil?

        CFG.default_dir = File.dirname(outpath)
        name = File.basename(outpath)

        File.open(outpath, 'w') do |file|
          svg = makesvg(name, *grps)
          svg.write(file)
        end
      end
      ################
      def process_selection(selset)
        # UI: process any selected faces and lay out into profile grp
        layout_facegrps(*selset.select(&:valid?).grep(Sketchup::Face))
      end

      ################
      def su_profilegrp(create: true)
        # Find or create the group for the profile entities
        unless @su_profilegrp&.valid?
          @su_profilegrp = Sketchup::active_model.entities.grep(Sketchup::Group)
                                   .find { |g| g.name==PROFILE_GROUP && g.valid? }
        end
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
        su_profilegrp.layer = Sketchup.active_model.layers[0]
        @su_profilegrp = Sketchup.active_model.entities
                                 .add_group(@su_profilegrp.explode + [facegrp])
        @su_profilelayer = Sketchup.active_model.layers.add(PROFILE_LAYER)
        @su_profilegrp.name = PROFILE_GROUP
        @su_profilegrp.layer = @su_profilelayer
      end
      ################
      def layout_facegrps(*su_faces)
        FaceSVG.capture_faceprofiles(*su_faces) do |new_entities, bnds|
          layout_xf = Geom::Transformation
                      .new([@layoutx, @layouty, 0.0])
          # explode, work around more weird behavior with Arcs?
          # Transform them and then add them back into a group
          Sketchup.active_model.entities.transform_entities(layout_xf, new_entities)

          newgrp = su_profilegrp.entities.add_group(new_entities)
          FaceSVG.dbg('Face %s  layout x,y %s %s', bnds, @layoutx, @layoutx)

          # Handle automatic corner relief
          if CFG.corner_relief == CR_SYMMETRIC_AUTO
            surface_faces = new_entities.grep(Sketchup::Face)
                                        .select { |face| face.material == FaceSVG.surface }
            Relief.relieve_face_corners(*surface_faces, CFG.bit_diameter/2, auto: true)
          end

          add_su_facegrp(newgrp)

          @layoutx += CFG.layout_spacing + bnds.width
          # As each element is layed out horizontally, keep track of the tallest bit
          @rowheight = [@rowheight, bnds.height].max
          if @layoutx > CFG.layout_width
            @layoutx = 0.0 + CFG.layout_spacing
            @layouty += @rowheight + CFG.layout_spacing
            @rowheight = 0.0
          end
        end
      end
    end
  end
end
