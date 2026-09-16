shader_type spatial;

// One mesh, two surfaces: which camera is drawing decides. Bit 4 is the fantasy visual layer
// (SplitDual.WORLD_BITS); a camera that sees it draws the fantasy surface, any other the scifi one.

uniform vec3 scifi_albedo : source_color = vec3(0.5);
uniform float scifi_metallic = 0.0;
uniform float scifi_roughness = 0.8;
uniform vec3 scifi_emission = vec3(0.0);
uniform vec3 fantasy_albedo : source_color = vec3(0.5);
uniform float fantasy_metallic = 0.0;
uniform float fantasy_roughness = 0.8;
uniform vec3 fantasy_emission = vec3(0.0);
uniform int fantasy_bits = 4;

void fragment() {
	bool fantasy = (CAMERA_VISIBLE_LAYERS & uint(fantasy_bits)) != uint(0);
	ALBEDO = fantasy ? fantasy_albedo : scifi_albedo;
	METALLIC = fantasy ? fantasy_metallic : scifi_metallic;
	ROUGHNESS = fantasy ? fantasy_roughness : scifi_roughness;
	EMISSION = fantasy ? fantasy_emission : scifi_emission;
}
