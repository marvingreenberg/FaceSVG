module FaceSVG
  # Simple vector class, less typing than builtin Sketchup types
  def self.V2d(*args)
    args = args[0].to_a if args.size == 1
    FaceSVG::Vn.new(args[0, 2])
  end

  def self.V3d(*args)
    args = args[0].to_a if args.size == 1
    FaceSVG::Vn.new(args[0, 2])
  end

  class Vn < Array
    # A simple vector supporting scalar multiply and vector add, dot
    # product, magnitude
    def initialize(elts); concat(elts); end
    def *(scalar); Vn.new(map { |c| c * scalar }); end
    def +(v2); Vn.new(zip(v2).map { |c, v| c + v }); end
    def -(v2); Vn.new(zip(v2).map { |c, v| c - v }); end
    def dot(v2); zip(v2).map { |c, v| c * v }.reduce(:+); end
    def abs(); map { |c| c * c }.reduce(:+)**0.5; end
    def ==(v2); (self - v2).abs < 0.005; end
    def inspect(); '(' + map { |c| '%0.3f' % c }.join(',') + ')'; end
    def to_s; inspect; end
    def x; self[0]; end
    def y; self[1]; end
  end

  # format a position with more brevity
  def self.pos_s(p)
    '(%s,%s,%s)' % p.to_a.map { |m| m.round(2) }
  end
  # Sometimes, code to duplicate arc gets end point off by some .01
  #  which screws up key.  So round keys to nearest 0.05

  # Compare two endpoints with tolerance
  TOLERANCE = 0.05
  def self.samepos(pos1, pos2)
    (pos1 - pos2).length < TOLERANCE
  end

  def self.debug(*args)
    puts(format(*args)) if ENV['FACESVG_DEBUG']
  end
end
