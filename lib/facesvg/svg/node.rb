# frozen_string_literal: true

module FaceSVG
  module SVG
    extend self

    class Node
      # Simple Node object to construct SVG XML output (no built in support for XML in ruby)
      # Only the paths need to be sorted,  so initialize with a 'z' value.
      # Everything is transformed to z=0 OR below.  So make exterior paths 2.0,
      # interior 1.0, and pocket cuts actual depth (negative offsets)

      def initialize(name, attrs: nil, text: nil)
        @name = name
        # attribute map
        # Default stuff (desc, title) ordered to top (1.0e20)
        @attrs = attrs.nil? ? {} : attrs.clone
        @extent = @attrs.delete('extent') || 1.0e20
        @text = text
        @children = []
      end

      attr_reader :extent

      def <=>(other)
        -(extent <=> other.extent) # minus, since bigger are first
      end

      def add_attr(name, value); @attrs[name] = value; end
      def add_text(text); @text = text; end

      def add_children(*nodes); @children.push(*nodes); end

      def write(file)
        file.write("\n<#{@name} ")
        @attrs.each { |k, v| file.write("#{k}='#{v}' ") } if @attrs
        if @children.length == 0 and not @text
          file.write('/>')
        else
          file.write('>')
          file.write(@text) if @text
          @children.sort.each { |c| c.write(file) }
          file.write("\n</#{@name}>")
        end
      end
    end
  end
end
