# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'
require 'LangHandler'
# TODO: language support (not much)
# TODO: windows testing
# TODO: support metric output mm,cm

module FaceSVG
  VERSION = '2.3.0'

  lang = LanguageHandler.new('facesvg')

  extension = SketchupExtension.new('Face SVG Export', 'facesvg/main')
  extension.creator     = 'Marvin Greenberg'
  extension.description = lang.GetString(
    'Tool to export faces as SVG.  Designed to support Shaper Origin.'
  )
  extension.version     = VERSION
  extension.copyright   = 'Marvin Greenberg, 2018, 2019, 2020'
  Sketchup.register_extension(extension, true)
end
