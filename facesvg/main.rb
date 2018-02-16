###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# redefine module if reloading plugin under sketchup
begin
  Object.send(:remove_const, :FaceSVG)
rescue
  true
end

Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/layout')
Sketchup.require('facesvg/su_util')

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
      @svg_output = SINGLE_FILE
      @units = FaceSVG.su_model_unit
      if @units == INCHES
        @layout_spacing = 0.5 # 1/2" spacing
        @layout_width = 24.0
        @pocket_max = 0.75
        @sheetheight = 24.0 # unused
        @cut_depth = 0.25
      else
        @layout_spacing = 1.5.cm # 1/2" spacing
        @layout_width = 625.mm
        @pocket_max = 2.0.cm
        @sheetheight = 625.mm # unused
        @cut_depth = 5.0.mm
      end
    end
    attr_accessor :units
    attr_accessor :cut_depth
    attr_accessor :default_dir
    attr_accessor :facesvg_version
    attr_accessor :layout_spacing
    attr_accessor :layout_width
    attr_accessor :pocket_max
    attr_accessor :svg_output
  end

  CFG = Configuration.new

  extend self # instead of 'def self' everywhere

  @@profilemap = Hash.new { |h, k| h[k] = Layout::ProfileCollection.new(k) }

  # On Mac, can have multiple open models, keep ProfileCollection for each model
  def profile()
    title = Sketchup.active_model.title or 'Untitled'
    @@profilemap[title]
  end

  def facesvg_2d_layout
    su_operation(LAYOUT_SVG) { profile().process_selection() }
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
               [SVG_OUTPUT, LAYOUT_WIDTH, LAYOUT_SPACING, POCKET_MAX, CUT_DEPTH],
               [CFG.svg_output, CFG.layout_width, CFG.layout_spacing, CFG.pocket_max, CFG.cut_depth],
               [SVG_OUTPUT_OPTS, '', '', '', ''],
               [FACESVG, SETTINGS].join(' '))
    CFG.svg_output, CFG.layout_width, CFG.layout_spacing, CFG.pocket_max, CFG.cut_depth = inputs if inputs
  rescue => excp
    _show_and_reraise(excp)
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
        # selset = Sketchup.active_model.selection
        s_m = context_menu.add_submenu(FACESVG)
        s_m.add_item(SETTINGS) { facesvg_settings }
        s_m.add_item(RESET_LAYOUT) { facesvg_reset }
        s_m.add_item(LAYOUT_SVG) { facesvg_2d_layout }
        s_m.add_item(WRITE_SVG) { facesvg_write } unless profile().empty?
      end

      @@context_menu_set = true
      # UI.messagebox "Loaded #{__FILE__}", MB_OK (debugging only)
      file_loaded(__FILE__)
    rescue => excp
      _show_and_reraise(excp)
    end
  end
end
