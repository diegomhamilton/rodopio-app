extends Node3D
## Optional 3D interaction study. Native plugin integration is a separate build step.
signal note_requested(midi: int)
var pads: Dictionary = {}
var labels := ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si", "Dó"]
var camera: Camera3D

func _ready() -> void:
    camera = Camera3D.new()
    add_child(camera)
    camera.position = Vector3(0, 10, 12)
    camera.look_at(Vector3.ZERO)
    var light := DirectionalLight3D.new()
    add_child(light)
    light.rotation_degrees = Vector3(-60, -20, 0)
    light.light_energy = 1.4
    for index in range(13):
        var angle := float(index) / 13.0 * TAU
        var pad := StaticBody3D.new()
        pad.set_meta("midi", 60 + index)
        add_child(pad)
        pad.position = Vector3(sin(angle) * 4, 0, cos(angle) * 4)
        var mesh := MeshInstance3D.new()
        var cylinder := CylinderMesh.new()
        cylinder.top_radius = 0.65
        cylinder.bottom_radius = 0.65
        cylinder.height = 0.3
        mesh.mesh = cylinder
        var material := StandardMaterial3D.new()
        material.albedo_color = Color("72dfb7") if not index in [1, 3, 6, 8, 10] else Color("30819a")
        mesh.material_override = material
        pad.add_child(mesh)
        var shape := CollisionShape3D.new()
        var collision := CylinderShape3D.new()
        collision.radius = 0.65
        collision.height = 0.3
        shape.shape = collision
        pad.add_child(shape)
        var label := Label3D.new()
        label.text = labels[index]
        label.position.y = 0.8
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.font_size = 64
        pad.add_child(label)
        pads[60 + index] = pad
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var title := Label.new()
    title.text = "CIRANDA · estudo visual 3D\nToque nos círculos. Áudio e rede estão no app iOS."
    title.position = Vector2(24, 24)
    title.add_theme_font_size_override("font_size", 22)
    canvas.add_child(title)

func _unhandled_input(event: InputEvent) -> void:
    var point: Vector2
    if event is InputEventScreenTouch and event.pressed:
        point = event.position
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        point = event.position
    else:
        return
    var origin := camera.project_ray_origin(point)
    var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 100)
    var result := get_world_3d().direct_space_state.intersect_ray(query)
    if not result.is_empty() and result.collider.has_meta("midi"):
        var midi: int = result.collider.get_meta("midi")
        note_requested.emit(midi)
        animate_note(midi)

func animate_note(midi: int) -> void:
    if not pads.has(midi):
        return
    var pad: StaticBody3D = pads[midi]
    var tween := create_tween()
    tween.tween_property(pad, "position:y", 0.55, 0.10)
    tween.tween_property(pad, "position:y", 0.0, 0.25)
