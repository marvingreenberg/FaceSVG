# frozen_string_literal: true

require 'sketchup'
require 'extensions'
require 'langhandler'
# TODO: language support (not much)
# TODO: more testing
# TODO: support metric output mm,cm

module FaceSVG
  VERSION = '3.0.2'

  lang = LanguageHandler.new('facesvg')

  extension = SketchupExtension.new('Face SVG Export', 'facesvg/main')
  extension.creator     = 'Marvin Greenberg'
  extension.description = lang.GetString(
    'Tool to export faces as SVG.  Designed to support Shaper Origin.'
  )
  extension.version     = VERSION
  extension.copyright   = 'Marvin Greenberg, 2018, 2019, 2020, 2023'
  Sketchup.register_extension(extension, true)
end
