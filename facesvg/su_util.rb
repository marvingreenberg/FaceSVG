Sketchup.require('facesvg/constants')
Sketchup.require('matrix')
Sketchup.require('logger')

module FaceSVG
  extend self
  def facesvg_dir(nocreate: false)
    d = File.join(FileUtils.pwd, 'facesvg')
    FileUtils.mkdir(d, mode: 0o755) unless nocreate || File.directory?(d)
    d
  end
  @@filelog = Logger.new(File.join(facesvg_dir(), 'debug.log'))
  @@filelog.datetime_format = '%H:%M:%S'

  # Make a unique configuration for each model
  @@cfgmap = Hash.new { |h, k| h[k] = Configuration.new }

  def same(num0, num1)
    (num0-num1).abs < TOLERANCE
  end

  # Materials to mark faces during processing
  def marker; mk_material('svg_marker', 'red'); end
  def surface; mk_material('svg_surface', cfg().fill_exterior_color); end
  def pocket; mk_material('svg_pocket', [160, 160, 160]); end

  # This seem unused for now
  # def annotation; mk_material('svg_annotation', cfg().annotation_color); end

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
    msg = excp.to_s + "\n" + excp.backtrace.reject(&:empty?).join("\n*")
    @@filelog.error(msg)
    UI.messagebox(msg)
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
        face_offset(face, other) < cfg().pocket_max
    }
  end

  # defaults
  class Configuration
    def initialize()
      @default_dir = nil # not persistent

      # Undocumented settings
      @confirmation_dialog = true
      @debug = true
      @annotation_color= [20, 110, 255] # "Shaper Blue"
      @stroke_interior_color = [0, 0, 0]
      @stroke_exterior_color = [0, 0, 0]
      @fill_interior_color = [255, 255, 255]
      @fill_exterior_color = [0, 0, 0]
      @pocket_base_values = [85, 85, 85]
      @fill_pocket_color = nil
      @stroke_pocket_color = nil

      @corner_relief = CR_NONE
      @file_mode = SINGLE
      # Keep separate dimension defaults for different settings
      # Ruby hash/dict syntax and rules are insane
      @dimensions = {
        INCHES => {
          BIT_SIZE => 0.25,
          CUT_DEPTH => 0.25, # unused
          LAYOUT_SPACING => 0.5, # 1/2" spacing
          LAYOUT_WIDTH => 24.0,
          POCKET_MAX => 0.76
        },
        MM => {
          BIT_SIZE => 6.35,
          CUT_DEPTH => 5.0, # unused
          LAYOUT_SPACING => 1.5,
          LAYOUT_WIDTH => 625.0,
          POCKET_MAX => 20.0
        }
      }

      load()
    end

    # CFG always stored as INCHES or MM
    def _unit() FaceSVG::su_model_unit == INCHES ? INCHES : MM end
    def _lbl(s) format('%s (%s.)', s, _unit()) end
    # return the stored "native-dimension" attribute value
    def _attr(name) @dimensions[_unit()][name] end
    # Units always stored in INCHES or MM, converted to inches when used
    def su_val(units, val)
      units==INCHES && val.to_f || val.to_f/25.4
    end
    # get/set the attr value, returning value as SU inches-always units
    def dimension(attr, val: nil)
      u = _unit()
      @dimensions[u][attr] = val if val
      su_val(u, @dimensions[u][attr])
    end
    # labels, values and options for input box in main.
    def labels()
      [_lbl(LAYOUT_WIDTH), _lbl(LAYOUT_SPACING),
       _lbl(POCKET_MAX), CORNER_RELIEF, _lbl(BIT_SIZE),
       FILE_MODE]
    end

    def values()
      [_attr(LAYOUT_WIDTH), _attr(LAYOUT_SPACING),
       _attr(POCKET_MAX), @corner_relief, _attr(BIT_SIZE),
       @file_mode]
    end

    def options()
      ['', '', '', CR_OPTIONS, '', FILE_OPTIONS]
    end

    def inputs(inputvals)
      (layout_width, layout_spacing,
       pocket_max, @corner_relief, bit_size, @file_mode) = inputvals
      # Ruby syntax is a mess
      dimension(LAYOUT_WIDTH, val: layout_width)
      dimension(LAYOUT_SPACING, val: layout_spacing)
      dimension(POCKET_MAX, val: pocket_max)
      dimension(BIT_SIZE, val: bit_size)
    end

    # Don't save units, since that comes from the model
    def to_hash()
      Hash[instance_variables.map { |var| [var.to_s, instance_variable_get(var)] }]
    end

    def save()
      File.open(File.join(FaceSVG::facesvg_dir(), 'settings.json'), 'w') do |f|
        f.write JSON.pretty_generate(to_hash(),
                                     space: '', indent: ' ', array_nl: ' ')
      end
    end
    def load()
      # overide defaults from saved settings
      settings_file = File.join(FaceSVG::facesvg_dir(nocreate: true), 'settings.json')
      return unless File.file?(settings_file)
      File.open(settings_file, 'r') { |f|
        JSON.parse(f.read()).each do |name, val|
          instance_variable_set(name, val)
        end
      }
    rescue StandardError => excp
      UI.messagebox(format('Error loading settings, %s renamed: %s',
                           settings_file, excp.to_s))
      File.rename(settings_file, settings_file+'.err')
    end

    # The accessor dimension() returns value in SU inches-always units
    attr_accessor :dimensions
    def bit_size() dimension(BIT_SIZE) end
    def cut_depth() dimension(CUT_DEPTH) end
    def layout_spacing() dimension(LAYOUT_SPACING) end
    def layout_width() dimension(LAYOUT_WIDTH) end
    def pocket_max() dimension(POCKET_MAX) end

    def bit_size=(val) dimension(BIT_SIZE, val: val) end
    def layout_spacing=(val) dimension(LAYOUT_SPACING, val: val) end
    def layout_width=(val) dimension(LAYOUT_WIDTH, val: val) end
    def pocket_max=(val) dimension(POCKET_MAX, val: val) end

    # Save the config whenever default dir is changed
    def default_dir=(val)
      return if val != @default_dir
      @default_dir = val
      save()
    end

    # True if multiple files
    def multifile_mode?() @file_mode == MULTIPLE end

    attr_reader :units
    attr_reader :corner_relief

    # Undocumented settings
    attr_reader :default_dir
    attr_reader :confirmation_dialog
    attr_reader :stroke_interior_color
    attr_reader :stroke_exterior_color
    attr_reader :fill_interior_color
    attr_reader :fill_exterior_color
    attr_reader :fill_pocket_color
    attr_reader :annotation_color
    attr_reader :debug
  end

  # Access a configuration instance
  def cfg()
    # On Mac, can have multiple open models, keep Separate CFG for each (units could be different)
    @@cfgmap[Sketchup.active_model.guid]
  end

  # Simple debugging method
  if cfg().debug
    def dbg(fmt, *args)
      @@filelog.debug(format(fmt+'\n', *args))
    end
  else
    def dbg(*args); end
  end
  def info(fmt, *args)
    @@filelog.info(format(fmt+'\n', *args))
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

    # Return a number that is a measure of the "extent" of the bounding box
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

      FaceSVG.dbg("capture_faceprofiles: #{related_faces}, #{bnds}")
      yield related_faces, bnds
    end
  end
end
