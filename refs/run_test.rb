# frozen_string_literal: true

module Sketchup
  extend self

  def self.require(path)
    Kernel::require(path)
  end
end

# module FaceSVG
#   module SVG
#     module Sketchup
#       def require(path)
#         load(path)
#       end
#     end
#   end
# end

# suppress erroneous solargraph require_not_found
def dorequire(path) require(path) end
dorequire('test/unit')

base_dir = File.expand_path(File.join(File.dirname(__FILE__), '.'))
lib_dir  = File.join(base_dir, 'lib')
test_dir = File.join(base_dir, 'test')
stubs_dir = File.join(base_dir, 'stubs')

$LOAD_PATH.unshift(stubs_dir, lib_dir)

require 'simplecov'
SimpleCov.start

exit Test::Unit::AutoRunner.run(true, test_dir)
