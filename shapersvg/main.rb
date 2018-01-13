###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# redefine module if reloading plugin under sketchup
begin
  Object.send(:remove_const, :ShaperSVG)
rescue => exception
  true
end

load 'shapersvg/layout.rb'

# $uStrings = LanguageHandler.new("shaperSVG")
# extensionSVG = SketchupExtension.new $uStrings.GetString("shaperSVG"), "shapersvg/shapersvg.rb"
# extensionSVG.description=$uStrings.GetString("Create SVG files from faces")
# Sketchup.register_extension extensionSVG, true

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes
# https://stackoverflow.com/questions/11503558/how-to-undefine-class-in-ruby

# TTD
# More settings material size 2x4 4x4, bit size 1/8, 1/4
# Look at
# https://www.codeproject.com/Articles/210979/Fast-optimizing-rectangle-packing-algorithm-for-bu
# for way to simply arrange the rectangles efficiently in layout, maybe overkill.

SPACING = 1.0 # 1" spacing
SHEETWIDTH = 48.0

module ShaperSVG

  ADDIN_VERSION = 'version:0.1'

  module Main

    extend self # Ruby is weird.  Make Main module act like a singleton class
    
    @@menus_set ||= false
    @@out_filename = '/Users/mgreenberg/example.svg'
    @@segments = true
    @@text = true
    @@xformer = {}
    
    # On Mac, can have multiple open models, keep separate tranfrom instance for each model
    def transformer()
      title = Sketchup::active_model.title or 'Untitled'
      xf = @@xformer[title] or ShaperSVG::Layout::Transformer.new
      @@xformer[title] = xf
    end
      
    def _handle(exception)
      UI.messagebox exception.backtrace.reject(&:empty?).join("\n**")
      UI.messagebox exception.to_s
    end

    def shapersvg_2d_layout
      transformer().process_selection()
    rescue => exception
      _handle(exception)
      raise
    end

    def shapersvg_write
      # Write the SVG file
      File.open(@@out_filename,'w') do |f|
        transformer().write(f)
      end
    rescue => exception
      _handle(exception)
      raise
    end
      
    def shapersvg_reset
      # Delete the cut path layout
      transformer().reset
    rescue => exception
      _handle(exception)
      raise
    end

    def shapersvg_toggle_mark_face(sel)
      transformer().toggle_mark_face(sel)
    end
    
    def shapersvg_settings
      # No real useful settings yet
      inputs = UI.inputbox(
        ["Output filename", "Segments", "Text"],
        [@@out_filename, @@segments, @@text],
        ["","on|off","on|off"],
        "--------                 SVG Export Settings                 -----------")
      @@out_filename, @@segments, @@text = inputs if inputs
    rescue => exception
      _handle(exception)
      raise
    end
    
    unless file_loaded?(__FILE__)  || @@menus_set
      begin
        # No point to static menu for now 
        # menu = UI.menu('Plugins')
        # menu.add_item('ShaperSVG 2D Layout') {
        #   shapersvg_2d_layout
        # }
        # menu.add_item('ShaperSVG Settings') {
        #   shapersvg_settings
        # }
        
        UI.add_context_menu_handler do |context_menu|
          selset = Sketchup::active_model.selection
          _sm = context_menu.add_submenu('Shaper')
          _sm.add_item('Reset SVG profile') { shapersvg_reset }
          _sm.add_item('Write SVG profile') { shapersvg_write }
          _sm.add_item('Layout SVG profile') { shapersvg_2d_layout }
          if selset.size > 1
            _sm.add_item('Mark/unmark face(s)') { shapersvg_toggle_mark_face(selset) }
          end
        end # context_menu_handler

        @@context_menu_set = true      
        UI.messagebox "Loaded #{__FILE__}", MB_OK
        file_loaded(__FILE__)
      rescue => exception
        _handle(exception)
        raise
      end
    end
  end
end
