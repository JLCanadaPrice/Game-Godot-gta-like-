shader_type spatial;

render_mode blend_mix, depth_draw_always, cull_back,
    diffuse_lambert, specular_schlick_ggx;


// ================================================================
// COLOR
// ================================================================

uniform vec4 shallow_color : source_color =
    vec4(0.10, 0.60, 0.70, 1.0);

uniform vec4 deep_color : source_color =
    vec4(0.01, 0.03, 0.12, 1.0);

uniform float depth_absorption : hint_range(0.01, 2.0, 0.01) = 0.4;

uniform float transparency : hint_range(0.0, 1.0, 0.05) = 0.9;


// ================================================================
// SURFACE WAVES
// ================================================================

uniform float wave_speed : hint_range(0.0, 3.0, 0.05) = 0.45;

uniform float wave_scale : hint_range(0.001, 2.0, 0.001) = 0.05;

uniform float wave_choppiness : hint_range(0.1, 10.0, 0.1) = 1.0;

uniform float normal_strength : hint_range(0.01, 5.0, 0.01) = 0.5;


// ================================================================
// VERTEX WAVES
// ================================================================

uniform float vertex_wave_height : hint_range(0.0, 2.0, 0.05) = 0.18;

uniform float vertex_wave_length : hint_range(1.0, 50.0, 1.0) = 18.0;


// ================================================================
// REFLECTION / FRESNEL
// ================================================================

uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.04;

uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.05;

uniform float fresnel_power : hint_range(0.5, 6.0, 0.1) = 3.0;

uniform float refraction_strength : hint_range(0.0, 0.1, 0.001) = 0.015;


// ================================================================
// FOAM
// ================================================================

uniform vec4 foam_color : source_color =
    vec4(0.95, 0.98, 1.0, 1.0);

uniform float shoreline_foam_distance :
    hint_range(0.0, 5.0, 0.05) = 0.8;

uniform float crest_foam_threshold :
    hint_range(0.0, 1.0, 0.05) = 0.6;


// ================================================================
// TEXTURES
// ================================================================

uniform sampler2D wave_normal_texture :
    hint_normal,
    filter_linear_mipmap_anisotropic,
    repeat_enable;

uniform sampler2D foam_texture :
    hint_default_white,
    filter_linear_mipmap,
    repeat_enable;

uniform sampler2D DEPTH_TEXTURE :
    hint_depth_texture,
    filter_linear_mipmap;

uniform sampler2D SCREEN_TEXTURE :
    hint_screen_texture,
    filter_linear_mipmap;


// ================================================================
// VARYINGS
// ================================================================

varying vec3 world_pos;

varying float vertex_height;


// ================================================================
// VERTEX
// ================================================================

void vertex()
{
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    float time = TIME * wave_speed;

    float amplitude = vertex_wave_height;

    float k = 6.2831853 / vertex_wave_length;


    // ------------------------------------------------------------
    // LARGE OCEAN SWELLS
    // ------------------------------------------------------------

    float large_wave_1 =
        sin(
            world_pos.x * k
            + world_pos.z * 0.17
            + time * 0.70
        );

    float large_wave_2 =
        cos(
            world_pos.z * (k * 0.87)
            - world_pos.x * 0.12
            + time * 0.50
        );

    float large_wave_3 =
        sin(
            world_pos.x * (k * 0.70)
            - world_pos.z * 0.22
            + time * 0.60
        );


    // ------------------------------------------------------------
    // MEDIUM WAVES
    // ------------------------------------------------------------

    float medium_wave_1 =
        sin(
            world_pos.x * 0.90
            + world_pos.z * 0.40
            + time * 1.15
        );

    float medium_wave_2 =
        cos(
            world_pos.z * 0.80
            - world_pos.x * 0.60
            + time * 0.90
        );

    float medium_wave_3 =
        sin(
            world_pos.x * -0.70
            + world_pos.z * 1.10
            + time * 1.25
        );


    // ------------------------------------------------------------
    // SMALL WAVES
    // ------------------------------------------------------------

    float small_wave_1 =
        sin(
            world_pos.x * 2.20
            + world_pos.z * 1.60
            + time * 1.80
        );

    float small_wave_2 =
        cos(
            world_pos.z * 2.00
            - world_pos.x * 1.40
            + time * 1.60
        );

    float small_wave_3 =
        sin(
            world_pos.x * -2.80
            + world_pos.z * 2.40
            + time * 2.00
        );


    // ------------------------------------------------------------
    // COMBINE
    // ------------------------------------------------------------

    float displacement =
          large_wave_1 * amplitude * 0.45
        + large_wave_2 * amplitude * 0.30
        + large_wave_3 * amplitude * 0.15

        + medium_wave_1 * amplitude * 0.18
        + medium_wave_2 * amplitude * 0.12
        + medium_wave_3 * amplitude * 0.08

        + small_wave_1 * amplitude * 0.035
        + small_wave_2 * amplitude * 0.020
        + small_wave_3 * amplitude * 0.015;


    // Apply wave displacement
    VERTEX.y += displacement;

    vertex_height = displacement;
}


// ================================================================
// FRAGMENT
// ================================================================

void fragment()
{
    // ------------------------------------------------------------
    // SURFACE NORMAL WAVES (Smooth Blending)
    // ------------------------------------------------------------

    vec2 uv = world_pos.xz * wave_scale;

    float time = TIME * wave_speed;


    vec2 uv1 = uv + vec2(time * 0.03, time * 0.02);
    vec2 uv2 = uv * 1.2 - vec2(time * 0.02, time * 0.03);
    vec2 uv3 = uv * 2.0 + vec2(time * -0.03, time * 0.01);


    vec3 normal_1 = texture(wave_normal_texture, uv1).rgb * 2.0 - 1.0;
    vec3 normal_2 = texture(wave_normal_texture, uv2).rgb * 2.0 - 1.0;
    vec3 normal_3 = texture(wave_normal_texture, uv3).rgb * 2.0 - 1.0;


    // Blended normal map calculation
    vec3 blended_normal = normalize(normal_1 + normal_2 * 0.5 + normal_3 * 0.25);
    blended_normal.xy *= wave_choppiness;
    blended_normal = normalize(mix(vec3(0.0, 0.0, 1.0), blended_normal, normal_strength));


    // ------------------------------------------------------------
    // DEPTH
    // ------------------------------------------------------------

    float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;

    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);

    vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);

    view_position.xyz /= view_position.w;

    float linear_depth = -view_position.z;

    float water_depth = linear_depth + VERTEX.z;


    // ------------------------------------------------------------
    // REFRACTION
    // ------------------------------------------------------------

    vec2 refract_offset = blended_normal.xy * refraction_strength;

    float ref_depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV + refract_offset).r;

    vec4 ref_view = INV_PROJECTION_MATRIX * vec4(
        vec3((SCREEN_UV + refract_offset) * 2.0 - 1.0, ref_depth_raw),
        1.0
    );

    ref_view.xyz /= ref_view.w;

    if (-ref_view.z + VERTEX.z < 0.0)
    {
        refract_offset = vec2(0.0);
    }

    vec3 background_color = texture(SCREEN_TEXTURE, SCREEN_UV + refract_offset).rgb;


    // ------------------------------------------------------------
    // WATER DEPTH COLOR
    // ------------------------------------------------------------

    float depth_factor = 1.0 - exp(-max(0.0, water_depth) * depth_absorption);

    vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_factor);


    // ------------------------------------------------------------
    // SHORE FOAM (Softened Edge)
    // ------------------------------------------------------------

    vec2 foam_uv = world_pos.xz * 0.1 + vec2(time * 0.02, time * 0.015);

    float foam_noise = texture(foam_texture, foam_uv).r;

    float shore_foam_raw = clamp(1.0 - water_depth / max(shoreline_foam_distance, 0.001), 0.0, 1.0);

    // Soft gradient fade for realistic foam blending
    float shore_foam = smoothstep(0.1, 0.8, shore_foam_raw * (foam_noise * 0.7 + 0.3));


    // ------------------------------------------------------------
    // CREST FOAM
    // ------------------------------------------------------------

    float crest_height = clamp(vertex_height / (vertex_wave_height + 0.01), 0.0, 1.0);

    float crest_foam = smoothstep(
        crest_foam_threshold,
        crest_foam_threshold + 0.15,
        crest_height * max(blended_normal.y, 0.0) * foam_noise
    );

    float total_foam = clamp(shore_foam + crest_foam, 0.0, 1.0);


    // ------------------------------------------------------------
    // FRESNEL
    // ------------------------------------------------------------

    float R0 = 0.02;

    float cos_theta = clamp(dot(blended_normal, VIEW), 0.0, 1.0);

    float fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, fresnel_power);


    // ------------------------------------------------------------
    // FINAL WATER COLOR
    // ------------------------------------------------------------

    float surface_mix = clamp(transparency * depth_factor + fresnel * 0.6, 0.0, 1.0);

    vec3 final_color = mix(background_color, water_color, surface_mix);

    // Apply Foam
    final_color = mix(final_color, foam_color.rgb, total_foam * foam_color.a);


    // ------------------------------------------------------------
    // OUTPUT
    // ------------------------------------------------------------

    ALBEDO = final_color;
    NORMAL_MAP = blended_normal * 0.5 + 0.5;
    ROUGHNESS = mix(roughness, 0.7, total_foam);
    METALLIC = mix(metallic, 0.0, total_foam);
    SPECULAR = mix(0.8, 0.0, total_foam);
    ALPHA = 1.0;
}