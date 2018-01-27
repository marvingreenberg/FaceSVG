require 'sketchup.rb'
require 'extensions.rb'
require 'LangHandler'
# TODO language support (not much)
# TODO windows testing
# TODO support metric output mm,cm

module FaceSVG
  $uStrings = LanguageHandler.new("facesvg")

  EXTENSION = SketchupExtension.new( 'Face SVG Export', 'facesvg/main.rb' )
  EXTENSION.creator     = 'Marvin Greenberg'
  EXTENSION.description = $uStrings.GetString(
    'Tool to export faces as SVG.  Designed to support Shaper Origin.')
  EXTENSION.version     = '1.0'
  EXTENSION.copyright   = 'Marvin Greenberg 2018'
  Sketchup.register_extension(EXTENSION, true)
end
