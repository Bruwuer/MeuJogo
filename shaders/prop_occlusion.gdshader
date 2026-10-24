// Flat-colored prop/building material that dithers away geometry standing between the camera and the
// player, so trees and rocks never hide the character. player_world_pos is a project-wide
// shader global updated every frame by World.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec3 player_world_pos;
global uniform vec3 main_camera_pos; // lets shadow passes (rendered from the light) skip the fade
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0); // glow (fire, lit windows)
uniform float fade_radius = 0.17; // fraction of the screen height
uniform float keep_ratio = 0.3; // share of pixels kept inside the faded area
uniform float depth_margin = 0.6; // meters in front of the player before fading starts

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb;
	vec4 player_view = VIEW_MATRIX * vec4(player_world_pos, 1.0);
	bool main_view = distance(CAMERA_POSITION_WORLD, main_camera_pos) < 1.0;
	if (main_view && -VERTEX.z < -player_view.z - depth_margin) {
		vec4 clip = PROJECTION_MATRIX * player_view;
		vec2 player_uv = clip.xy / clip.w * 0.5 + 0.5;
		vec2 d = (SCREEN_UV - player_uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
		float fade = smoothstep(fade_radius, fade_radius * 0.7, length(d));
		float keep = mix(1.0, keep_ratio, fade);
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER[p.y * 4 + p.x] + 0.5) / 16.0 > keep) {
			discard;
		}
	}
}
