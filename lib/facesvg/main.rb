# frozen_string_literal: true

##########################################################
# Licensed under the MIT license
##########################################################
require 'sketchup'
require 'extensions'
require 'langhandler'

# redefine module if reloading plugin under sketchup
begin
  Object.send(:remove_const, :FaceSVG)
rescue
  true
end

require('facesvg/constants')
require('facesvg/layout')
require('facesvg/relief/util')
require('facesvg/su_util')

# API is strange - many operations create only approximate edges, but maintain accurate
#   circular or elliptical arc metadata separately.

# TODO: bit size 1/8, 1/4
# TODO: Look at?  Probably way overkill
# https://www.codeproject.com/Articles/210979/Fast-optimizing-rectangle-packing-algorithm-for-bu
# for way to simply arrange the rectangles efficiently in layout, maybe overkill.

module FaceSVG
  VERSION = Sketchup.extensions.find { |e| e.name == 'Face SVG Export' }.version
  # defaults
  class Configuration
    def initialize()
      @default_dir = nil
      @units = FaceSVG.su_model_unit
      @corner_relief = CR_NONE
      if @units == INCHES
        @layout_spacing = 0.5 # 1/2" spacing
        @layout_width = 24.0
        @pocket_max = 0.75
        @sheetheight = 24.0 # unused
        @cut_depth = 0.25
        @bit_diameter = 0.25
      else
        @layout_spacing = 1.5.cm # 1/2" spacing
        @layout_width = 625.mm
        @pocket_max = 2.0.cm
        @sheetheight = 625.mm # unused
        @cut_depth = 5.0.mm
        @bit_diameter = 8.0.mm
      end
    end
    attr_accessor :units, :bit_diameter, :cut_depth, :default_dir, :facesvg_version, :layout_spacing, :layout_width,
                  :pocket_max, :corner_relief
  end

  CFG = Configuration.new

  extend self # instead of 'def self' everywhere

  @@profilemap = Hash.new { |h, k| h[k] = Layout::ProfileCollection.new(k) }

  # On Mac, can have multiple open models, keep ProfileCollection for each model
  def profile()
    title = Sketchup.active_model.title or 'Untitled'
    @@profilemap[title]
  end

  def facesvg_2d_layout(selset)
    su_operation(LAYOUT_SVG) { profile().process_selection(selset) }
  end

  def corner_relief_available(selset)
    CFG.corner_relief != CR_NONE && (
      selset.find { |e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face) })
  end
  def facesvg_corner_relief(selset)
    # Can do: symmetric corner relief on a face, or on an edge and connected edges
    # Can do: asymmetric corner relief on a single edge on a face
    su_operation(LAYOUT_SVG) { Relief.relieve_corners(selset) }
  end

  def facesvg_write
    # Write the SVG file
    su_operation('write', transaction: false) { profile().write() }
  end

  # Almost pointless? If can undo the layout state, it would be...
  #  could make the information an attribute on the profile group...
  def facesvg_reset
    # Delete the cut path layout
    su_operation(RESET_LAYOUT) { profile().reset() }
  end

  def facesvg_settings
    inputs = UI
             .inputbox(
               [LAYOUT_WIDTH, LAYOUT_SPACING, POCKET_MAX, CUT_DEPTH, CORNER_RELIEF, BIT_DIAMETER],
               [CFG.layout_width, CFG.layout_spacing, CFG.pocket_max,
                CFG.cut_depth, CFG.corner_relief, CFG.bit_diameter],
               ['', '', '', '', CR_OPTIONS, ''],
               [FACESVG, SETTINGS].join(' '))
    if inputs
      (CFG.layout_width, CFG.layout_spacing, CFG.pocket_max,
        CFG.cut_depth, CFG.corner_relief, CFG.bit_diameter) = inputs
    end
  rescue => e
    su_show_and_reraise(e)
  end

  unless file_loaded?(__FILE__)
    begin
      # No point to static menu for now
      # menu = UI.menu('Plugins')
      # menu.add_item('FaceSVG 2D Layout') {
      #   facesvg_2d_layout
      # }
      # menu.add_item('FaceSVG Settings') {
      #   facesvg_settings
      # }

      UI.add_context_menu_handler do |context_menu|
        selset = Sketchup.active_model.selection
        s_m = context_menu.add_submenu(FACESVG)
        s_m.add_item(SETTINGS) { facesvg_settings }
        s_m.add_item(RESET_LAYOUT) { facesvg_reset }

        unless selset.grep(Sketchup::Face).empty?
          s_m.add_item(LAYOUT_SVG) {
            facesvg_2d_layout(selset)
          }
        end

        if corner_relief_available(selset)
          s_m.add_item(CORNER_RELIEF) {
            facesvg_corner_relief(selset)
          }
        end

        s_m.add_item(WRITE_SVG) { facesvg_write } unless profile().empty?
      end

      @@context_menu_set = true
      # UI.messagebox "Loaded #{__FILE__}", MB_OK (debugging only)
      file_loaded(__FILE__)
    rescue => e
      su_show_and_reraise(e)
    end
  end
end
