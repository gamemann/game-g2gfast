extends Node3D

const G2GPaths := preload("g2g_paths.gd")
const G2GUnits := preload("g2g_units.gd")

## The player's own flashlight: a cone from just beside the eye, drawn on this screen only.
##
## [b]Two lights, because this game draws two kinds of surface.[/b] Everything built in
## code — the hand-written maps, the players, the props, the hunters — is ordinarily
## shaded, and a [SpotLight3D] lights it. Every IMPORTED map is `unshaded` on purpose
## (`g2g_bsp_lightmapped.gdshader`: the lightmap the map's compiler baked IS its lighting),
## and an unshaded surface ignores every light in the scene — so a spotlight alone lights
## the hand-built maps and nothing at all on the maps people actually play, which is where
## a flashlight was asked for.
##
## So the two BSP shaders compute the cone themselves, from a 4 x 1 float texture this node
## rewrites every frame and hands to both shaders as a DEFAULT texture parameter:
##
## [codeblock]
## texel 0   position (world, metres)         on (1) / off (0)
## texel 1   direction (unit)                 cos of the outer half-angle
## texel 2   colour x energy                  range (metres)
## texel 3   cos of the inner half-angle      reference distance (metres)
## [/codeblock]
##
## [b]A default texture parameter rather than a global shader uniform, and the reason is
## pack delivery.[/b] A `global uniform` has to be declared in the host project's settings
## or the shader does not compile, and this game is delivered into a client shell whose
## `project.godot` it does not own — one undeclared global and every imported map draws
## nothing. A default texture is a property of the [Shader] resource: every material that
## leaves the parameter unset (all of them) reads it, the shader compiles the same with or
## without it, and a black default reads as "off". One texture, rewritten once a frame,
## for every surface of every map.
##
## [b]Shaped after the flashlight the imported maps were built around:[/b] a cone a little
## over fifty degrees across with a brighter core, carried just right of and below the eye,
## falling off with distance and gone by about 750 units, a warm white, and a click when it
## goes on and off. It trails the view by a frame or two rather than being bolted to it,
## which is what makes a moving light read as held rather than as a projector on the head.
##
## [b]Client-side, and never replicated.[/b] Nobody else sees it, so nobody can be blinded
## by somebody else's on a dark section, and it costs the netcode nothing. The server's
## only say is `sv_flashlight`, which arrives in the RULES event as [member allowed].

const CHANNEL := "g2g.flashlight"

## The parameter both BSP shaders read. Declared there with `hint_default_black`.
const SHADER_PARAMETER := &"flashlight_tex"

## The shaders an imported map draws with. Loaded through the same rebase the map uses, so
## this is the same [Shader] resource the materials hold rather than a second copy.
const SHADER_PATHS: Array[String] = [
	"res://game/g2g_bsp_lightmapped.gdshader",
	"res://game/g2g_bsp_translucent.gdshader",
]

## Full width of the cone, degrees.
@export_range(10.0, 120.0, 1.0) var cone_degrees: float = 54.0

## Full width of the bright core inside it, degrees.
@export_range(1.0, 120.0, 1.0) var core_degrees: float = 22.0

## How far it reaches, in genre units. The light is gone at this distance.
@export_range(64.0, 4096.0, 1.0) var range_units: float = 750.0

## Distance, in genre units, at which the light is at full strength; it falls off as one
## over the distance beyond it, the way the genre's own flashlight is attenuated.
@export_range(1.0, 1024.0, 1.0) var reference_units: float = 150.0

## Warm white. The genre's flashlight is not blue.
@export var colour: Color = Color(1.0, 0.94, 0.82)

## Brightness on the imported maps' surfaces, which are lit as albedo x (lightmap + this).
@export_range(0.0, 8.0, 0.05) var energy: float = 1.1

## Brightness of the [SpotLight3D] on everything else. Godot's units, not the shader's.
@export_range(0.0, 32.0, 0.1) var spot_energy: float = 3.0

## Where the light is carried, relative to the eye, in genre units: right, up, forward.
@export var offset_units: Vector3 = Vector3(6.0, -6.0, 0.0)

## How quickly the beam catches the view, per second. Higher is stiffer; 0 bolts it on.
@export_range(0.0, 200.0, 1.0) var follow_rate: float = 30.0

## Whether the server allows it. False switches it off and keeps it off.
var allowed: bool = true:
	set(value):
		allowed = value
		if not allowed and on:
			set_on(false)

## Whether it is on.
var on: bool = false

## The light for ordinarily-shaded surfaces.
var spot: SpotLight3D = null

var _image: Image = null
var _texture: ImageTexture = null
var _shaders: Array[Shader] = []
var _basis := Basis.IDENTITY
var _placed := false

signal toggled(is_on: bool)


func _ready() -> void:
	# Top level: the light is placed in world space every frame from the eye it is given,
	# and must not inherit whatever this node is parented under.
	top_level = true

	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = colour
	spot.light_energy = spot_energy
	spot.spot_range = G2GUnits.to_metres(range_units)
	spot.spot_angle = cone_degrees * 0.5
	spot.spot_angle_attenuation = 1.6
	spot.spot_attenuation = 1.0
	spot.shadow_enabled = not DotPlatform.is_web()
	spot.visible = false
	add_child(spot)

	_image = Image.create(4, 1, false, Image.FORMAT_RGBAF)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)

	for path in SHADER_PATHS:
		var shader := load(G2GPaths.rebase(path)) as Shader
		if shader == null:
			continue
		shader.set_default_texture_parameter(SHADER_PARAMETER, _texture)
		_shaders.append(shader)


## Takes the default texture back off the shaders, so a later client in the same process
## — a map change rebuilds nothing here, but a reconnect builds a whole new client — never
## reads a texture whose owner is gone.
func _exit_tree() -> void:
	for shader in _shaders:
		if shader != null:
			shader.set_default_texture_parameter(SHADER_PARAMETER, null)
	_shaders.clear()


## Switches it. Refused, and false, when the server does not allow it.
func set_on(value: bool) -> bool:
	if value and not allowed:
		return false

	if on == value:
		return true

	on = value
	_placed = false
	if spot != null:
		spot.visible = on
	if not on:
		_write_off()
	toggled.emit(on)
	DotLog.debug(CHANNEL, "flashlight", {"on": on})
	return true


func toggle() -> bool:
	return set_on(not on)


## Puts the beam at [param eye], pointing where it faces. Once a frame, from the client.
func present(delta: float, eye: Transform3D) -> void:
	if not on:
		return

	var target := eye.basis.orthonormalized()

	if not _placed or follow_rate <= 0.0:
		_basis = target
		_placed = true
	else:
		# Exponential, so the lag is the same at 60 frames a second and at 240.
		_basis = _basis.slerp(target, 1.0 - exp(-follow_rate * delta)).orthonormalized()

	var offset := G2GUnits.to_metres(1.0) * offset_units
	var origin := eye.origin + target.x * offset.x + target.y * offset.y - target.z * offset.z

	global_transform = Transform3D(_basis, origin)

	var forward := -_basis.z
	var outer := cos(deg_to_rad(cone_degrees * 0.5))
	var inner := cos(deg_to_rad(minf(core_degrees, cone_degrees) * 0.5))
	var lit := Color(colour.r * energy, colour.g * energy, colour.b * energy)

	_image.set_pixel(0, 0, Color(origin.x, origin.y, origin.z, 1.0))
	_image.set_pixel(1, 0, Color(forward.x, forward.y, forward.z, outer))
	_image.set_pixel(2, 0, Color(lit.r, lit.g, lit.b, G2GUnits.to_metres(range_units)))
	_image.set_pixel(3, 0, Color(inner, G2GUnits.to_metres(reference_units), 0.0, 0.0))
	_texture.update(_image)


func _write_off() -> void:
	if _image == null:
		return

	_image.fill(Color(0, 0, 0, 0))
	_texture.update(_image)


func describe() -> Dictionary:
	return {
		"allowed": allowed,
		"on": on,
		"shaders": _shaders.size(),
		"cone": cone_degrees,
		"range_units": range_units,
	}
