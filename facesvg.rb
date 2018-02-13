require 'sketchup.rb'
require 'extensions.rb'
require 'LangHandler'
# TODO: language support (not much)
# TODO: windows testing
# TODO: support metric output mm,cm

module FaceSVG
  lang = LanguageHandler.new('facesvg')

  extension = SketchupExtension.new('Face SVG Export', 'facesvg/main.rb')
  extension.creator     = 'Marvin Greenberg'
  extension.description = lang.GetString(
    'Tool to export faces as SVG.  Designed to support Shaper Origin.'
  )
  extension.version     = '1.0.1'
  extension.copyright   = 'Marvin Greenberg, 2018'
  Sketchup.register_extension(extension, true)
end
