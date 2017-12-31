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

require 'shapersvg/layout'

UI.messagebox "Starting load"

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
# for way to simply arrange the rectangles efficiently

SPACING = 1.0 # 1" spacing
SHEETWIDTH = 48.0


module ShaperSVG

  ADDIN_VERSION = 'version:0.1'

  module Main
    
    @@out_filename = '/Users/mgreenberg/example.svg'
    @@segments = true
    @@text = true

    def self.shapersvg_2d_layout
      lt = ShaperSVG::Layout::Transformer.new
      Sketchup::active_model.selection.each { |s| lt.process(s) }
      File.open(@@out_filename,'w') do |f|
        lt.write(f)
      end
    rescue => exception
      puts exception.backtrace.reject(&:empty?).join("\n**")
      puts  exception.to_s
      
      UI.messagebox exception.backtrace.reject(&:empty?).join("\n**")
      UI.messagebox exception.to_s
      raise
    end
  
    def self.shapersvg_settings
      puts "hello export_settings"
      inputs = UI.inputbox(
        ["Output filename", "Segments", "Text"],
        [@@out_filename, @@segments, @@text],
        ["","on|off","on|off"],
        "---------- SVG Export Settings -----------")
      @@out_filename, @@segments, @@text = inputs if inputs
    end
  end
end
