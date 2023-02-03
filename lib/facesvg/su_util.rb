# frozen_string_literal: true

require('facesvg/constants')
require('facesvg/bounds')
require('facesvg/svg/util')
Sketchup.require('matrix')
require('digest')
require('json')

module FaceSVG
  extend self

  if ENV['FACESVG_DEBUG']
    def dbg(fmt, *args)
      puts format(fmt, *args)
    end
  else
    def dbg(*args); end
  end

  def marker; mk_material('svg_marker', 'blue'); end
  def surface; mk_material('svg_surface', [0, 0, 0]); end
  def pocket; mk_material('svg_pocket', [165, 165, 165]); end

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
  rescue => e
    Sketchup.active_model.abort_operation() if transaction
    su_show_and_reraise(e)
  end

  def su_show_and_reraise(excp)
    UI.messagebox(
      "#{excp}\n #{excp.backtrace.reject(&:empty?).join("\n*")}")
    raise
  end

  ################
  def su_mark(saved_properties, *f_ary)
    f_ary.each do |face|
      saved_properties[face.entityID] = [face.material, face.layer]
      face.material = FaceSVG.marker
    end
  end

  def su_marked?
    proc { |face|
      face.is_a?(Sketchup::Face) && face.valid? && face.material == FaceSVG.marker
    }
  end

  def su_unmark(saved_properties, *f_ary)
    f_ary.select(&su_marked?).each do |face|
      # Reapply the saved material, popping it from the hash
      face.material, face.layer = saved_properties.delete(face.entityID)
    end
  end

  def su_face_offset(face, other)
    other.vertices[0].position.distance_to_plane(face.plane)
  end

  def su_related_faces?(face)
    # All the faces on the same "side"
    proc { |other|
      (face.normal % other.normal ==
        face.normal.length * other.normal.length) &&
        su_face_offset(face, other) < CFG.pocket_max
    }
  end

  # At this point the faces are all parallel to z=0 plane
  # Plane array a,b,c,d -> d is the height
  def annotate_related_faces(face)
    # Find faces at same z as selected face
    proc { |r|
      r.material = SVG.same(face.plane[3], r.plane[3]) ? FaceSVG.surface : FaceSVG.pocket
    }
  end

  # Want to copy all the connected faces (to keep arc edge metadata) and
  #  then delete all the faces that are "unrelated" to the selected face
  # while transforming everything to z=0 plane, ( or nearby :-) )
  # If the chain of transforms has a negative determinant, it has one reflection

  def reflection?(face)
    # See if the transformations on the selected face result in a reflection.
    # All the other transformations don't matter since are already transforming
    # and rotating to get it into XY plane.  But a reflection needs inclusion
    # Get the selected face, and find all transforms associated with it and parents
    transforms = (face.model.active_path || [])
                 .map(&:transformation) + [face.model.edit_transform]
    prod = transforms.reduce(&:*).to_a
    # Use ruby 3x3 Matrix to get determinant
    (Matrix.columns([prod[0, 3], prod[4, 3], prod[8, 3]]).determinant < 0)
  end

  def capture_faceprofiles(*f_ary)
    # Yields facegroup, face  (copied selection)
    orig_face_properties = {} # Save face material, layer through copy
    # mark the face(s) selected to copy
    su_mark(orig_face_properties, *f_ary)

    # If more than one face in all_connected,
    # they are unmarked after processing the first time,
    # Each face (or set of connected faces) is copied in its own group.
    f_ary.each do |face|
      next unless su_marked?.call(face)

      # This has to be done before the edit is closed because Sketchup is incomprehensible
      has_refl = reflection?(face)

      tmp = Sketchup.active_model.entities.add_group(face.all_connected)
      # Make xf to rotate selected face parallel to z=0, move all to
      #   quadrant to avoid itersecting existing geometry
      xf = Geom::Transformation.new(tmp.bounds.max, face.normal).inverse
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
      su_unmark(orig_face_properties, *face.all_connected)

      new_faces = new_entities.grep(Sketchup::Face)
      # Find originally selected (copied) face, could be >1, use first
      face = new_faces.find(&su_marked?)
      # Find the "related" faces, same plane or small offset (pocket)
      related_faces = new_faces
                      .grep(Sketchup::Face).select(&su_related_faces?(face))
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
