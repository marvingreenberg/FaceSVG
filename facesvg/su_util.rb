Sketchup.require('facesvg/constants')
Sketchup.require('matrix')

module FaceSVG
  extend self

  def same(num0, num1)
    (num0-num1).abs < TOLERANCE
  end

  def marker; mk_material('svg_marker', 'red'); end
  def surface; mk_material('svg_surface', CFG.fill_color_outside); end
  def pocket; mk_material('svg_pocket', CFG.fill_color_pocket); end

  def mk_material(name, color)
    m = Sketchup::active_model.materials[name]
    m = Sketchup::active_model.materials.add(name) if (m.nil? || !m.valid?)
    m.color = color
    m
  end

  def su_close_active()
    # Close any open edits, important when interacting with global model
    while Sketchup.active_model.close_active do; end
  end

  def su_model_unit()
    i = Sketchup::active_model.options['UnitsOptions']['LengthUnit']
    [INCHES, 'ft', MM, CM, 'm'][i]
  end

  def su_operation(opname, transaction: true)
    # Perform an operation, display or log traceback.  if transaction: true
    # (default) all SU calls are collected into an undo transaction with 'opname'
    Sketchup.active_model.start_operation(opname) if transaction
    yield
    Sketchup.active_model.commit_operation() if transaction
  rescue => excp
    Sketchup.active_model.abort_operation() if transaction
    _show_and_reraise(excp)
  end

  def _show_and_reraise(excp)
    UI.messagebox(
      excp.to_s + "\n" + excp.backtrace.reject(&:empty?).join("\n*"))
    raise
  end

  ################
  def mark(saved_properties, *f_ary)
    f_ary.each do |f|
      saved_properties[f.entityID] = [f.material, f.layer]
      f.material = FaceSVG.marker
    end
  end

  def marked?
    proc { |f|
      f.is_a?(Sketchup::Face) && f.valid? && f.material == FaceSVG.marker
    }
  end

  def unmark(saved_properties, *f_ary)
    f_ary.select(&marked?).each do |f|
      # Reapply the saved material, popping it from the hash
      f.material, f.layer = saved_properties.delete(f.entityID)
    end
  end

  def face_offset(face, other)
    other.vertices[0].position.distance_to_plane(face.plane)
  end

  def related_faces?(face)
    # All the faces on the same "side"
    proc { |other|
      (face.normal % other.normal ==
        face.normal.length * other.normal.length) &&
        face_offset(face, other) < CFG.pocket_max
    }
  end

  # defaults
  class Configuration
    def initialize()
      @default_dir = nil # not persistent

      # Undocumented settings
      @debug = false
      @annotation_color= 'blue'
      @stroke_color = [0, 0, 0]
      @fill_color_inside = [255, 255, 255]
      @fill_color_outside = [0, 0, 0]
      @fill_color_pocket = [165, 165, 165]

      @units = FaceSVG.su_model_unit
      @corner_relief = CR_NONE
      @multifile_mode = SINGLE_FILE
      if @units == INCHES
        @bit_diameter = 0.25
        @cut_depth = 0.25 # unused
        @layout_spacing = 0.5 # 1/2" spacing
        @layout_width = 24.0
        @pocket_max = 0.76
      else
        @bit_diameter = 8.0.mm
        @cut_depth = 5.0.mm # unused
        @layout_spacing = 1.5.cm # 1/2" spacing
        @layout_width = 625.mm
        @pocket_max = 2.0.cm
      end
      load()
    end

    # Unset settings are just nil
    def send(*args)
      __send__(*args)
    rescue NoMethodError
      nil
    end

    # Don't save units, since that comes from the model
    def to_hash()
      {
        'bit_diameter' => @bit_diameter,
        'cut_depth' => @cut_depth,
        'corner_relief' => @corner_relief,
        'layout_spacing' => @layout_spacing,
        'layout_width' => @layout_width,
        'pocket_max' => @pocket_max,
        'debug' => @debug,
        'annotation_color' => @annotation_color,
        'stroke_color' => @stroke_color,
        'fill_color_pocket' => @fill_color_pocket,
        'fill_color_inside' => @fill_color_inside,
        'fill_color_outside' => @fill_color_outside
      }
    end

    def load()
      return unless File.file?('.facesvg/settings.json')
      File.open('.facesvg/settings.json', 'r') { |f|
        JSON.parse(f.read()).each do |name, val| send(name+'=', val) end
      }
    rescue StandardError => excp
      UI.messagebox('Error loading settings: ' + FileUtils.pwd + '/.facesvg/settings.json: ' + excp.to_s)
    end

    attr_accessor :multifile_mode
    attr_accessor :units
    attr_accessor :bit_diameter
    attr_accessor :cut_depth
    attr_accessor :default_dir
    attr_accessor :facesvg_version
    attr_accessor :layout_spacing
    attr_accessor :layout_width
    attr_accessor :pocket_max
    attr_accessor :corner_relief

    # Undocumented settings
    attr_accessor :stroke_color
    attr_accessor :fill_color_inside
    attr_accessor :fill_color_outside
    attr_accessor :fill_color_pocket
    attr_accessor :annotation_color
    attr_accessor :debug
  end

  # Global configuration instance
  CFG = Configuration.new

  # Simple debugging method
  if CFG.debug
    def dbg(fmt, *args)
      puts format(fmt, *args)
    end
  else
    def dbg(*args); end
  end

  class Bounds
    # Convenience wrapper around a bounding box, accumulate the bounds
    #  of related faces and create a transform to move highest face
    #  to z=0, and min x,y to 0,0
    # BoundingBox width and height methods are undocumented nonsense, ignore them
    def initialize()
      @bounds = Geom::BoundingBox.new
    end
    def update(*e_ary)
      e_ary.each { |e| @bounds.add(e.bounds) }
      self
    end

    # Return a number that is a measure of the "extent" if the bounding box
    def extent; @bounds.diagonal; end
    def width; @bounds.max.x - @bounds.min.x; end
    def height; @bounds.max.y - @bounds.min.y; end
    def min; @bounds.min; end
    def max; @bounds.max; end
    def to_s; format('Bounds(min %s max %s)', @bounds.min, @bounds.max); end

    def shift_transform
      # Return a transformation to move min to 0,0, and shift bounds accordingly
      Geom::Transformation
        .new([1.0, 0.0, 0.0, 0.0,
              0.0, 1.0, 0.0, 0.0,
              0.0, 0.0, 1.0, 0.0,
              -@bounds.min.x, -@bounds.min.y, -@bounds.max.z, 1.0])
    end
  end

  # At this point the faces are all parallel to z=0 plane
  # Plane array a,b,c,d -> d is the height
  def annotate_related_faces(face)
    # Find faces at same z as selected face
    proc { |r|
      r.material = same(face.plane[3], r.plane[3]) ? FaceSVG.surface : FaceSVG.pocket
    }
  end

  # Want to copy all the connected faces (to keep arc edge metadata) and
  #  then delete all the faces that are "unrelated" to the selected face
  # while transforming everything to z=0 plane, ( or nearby :-) )
  # If the chain of transforms has a negative determinant, it has one reflection

  def reflection?(f)
    # See if the transformations on the selected face result in a reflection.
    # All the other transformations don't matter since are already transforming
    # and rotating to get it into XY plane.  But a reflection needs inclusion
    # Get the selected face, and find all transforms associated with it and parents
    transforms = (f.model.active_path || [])
                 .map(&:transformation) + [f.model.edit_transform]
    prod = transforms.reduce(&:*).to_a
    # Use ruby 3x3 Matrix to get determinant
    (Matrix.columns([prod[0, 3], prod[4, 3], prod[8, 3]]).determinant < 0)
  end

  def capture_faceprofiles(*f_ary)
    # Yields facegroup, face  (copied selection)
    orig_face_properties = {} # Save face material, layer through copy
    # mark the face(s) selected to copy
    mark(orig_face_properties, *f_ary)

    # If more than one face in all_connected,
    # they are unmarked after processing the first time,
    # Each face (or set of connected faces) is copied in its own group.
    f_ary.each do |f|
      next unless marked?.call(f)

      # This has to be done before the edit is closed because Sketchup is incomprehensible
      has_refl = reflection?(f)

      tmp = Sketchup.active_model.entities.add_group(f.all_connected)
      # Make xf to rotate selected face parallel to z=0, move all to
      #   quadrant to avoid itersecting existing geometry
      xf = Geom::Transformation.new(tmp.bounds.max, f.normal).inverse
      # Duplicate into a new group, switching to global context
      #  (close open edits, if in group or component edit)
      su_close_active()

      # Assuming (since no f-ing documentation) Sketchup if post-multiply
      xf = Geom::Transformation.scaling(-1.0, 1.0, 1.0) * xf if has_refl

      new_grp = Sketchup.active_model.entities.add_instance(tmp.definition, xf)
      # explode, creates the new entities, selecting all resulting faces, edges.
      new_entities = new_grp.explode.select { |e|
        e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
      }

      # unmark before explode tmp, face entityIDs change upon explode
      unmark(orig_face_properties, *f.all_connected)

      new_faces = new_entities.grep(Sketchup::Face)
      # Find originally selected (copied) face, could be >1, use first
      face = new_faces.find(&marked?)
      # Find the "related" faces, same plane or small offset (pocket)
      related_faces = new_faces
                      .grep(Sketchup::Face).select(&related_faces?(face))
                      .each(&annotate_related_faces(face))

      # Delete copied faces, that were not originally selected and not "related"
      related_faces_and_edges = (related_faces + related_faces.map(&:edges)).flatten
      Sketchup.active_model.entities
              .erase_entities(new_entities - related_faces_and_edges)

      # related_faces_and_edges = related_faces_and_edges.select(&:valid?)

      bnds = Bounds.new.update(*related_faces)
      Sketchup.active_model.entities
              .transform_entities(bnds.shift_transform, related_faces)

      # Finally, explode the original face, back to as it was
      tmp.explode

      yield related_faces, bnds
    end
  end
end
