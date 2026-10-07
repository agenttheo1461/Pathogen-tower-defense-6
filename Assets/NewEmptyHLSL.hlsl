// ToonRampLit.shader  v7
// Includes Custom Light Array to bypass URP tile-culling limits on mobile/desktop.

Shader "Custom/ToonRampLit"
{
    Properties
    {
        [Header(Base)]
        _BaseMap   ("Albedo",     2D)    = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)

        [Header(Cel Bands)]
        _DarkColor      ("Dark Band Color",     Color)           = (0.10, 0.13, 0.25, 1)
        _MidColor       ("Mid Band Color",      Color)           = (0.45, 0.50, 0.65, 1)
        _MidThreshold   ("Dark to Mid Edge",    Range(0.01,0.6)) = 0.30
        _LitThreshold   ("Mid to Lit Edge",     Range(0.1, 0.9)) = 0.60
        _AmbientStr     ("Ambient Floor",       Range(0, 1))     = 0.25
        _LightColorInfluence ("Light Color Influence", Range(0,1)) = 0.35

        [Header(Surface  works for every material)]
        _Smoothness    ("Smoothness (highlight tightness)", Range(0,1)) = 0.5
        _Metallic      ("Metallic (0=paint/plastic, 1=bare metal)", Range(0,1)) = 0.0
        _SpecularColor ("Specular Tint (non-metallic only)", Color)   = (1,0.95,0.82,1)
        _SpecularIntensity ("Specular Intensity", Range(0,2)) = 0.6
        _ClearcoatStr  ("Clearcoat / Env Reflection (opaque surfaces)", Range(0,1)) = 0.0
        _SelfLit       ("Self-Lit Amount (neon/emissive glow)", Range(0,1)) = 0.0

        [Header(Weathering  optional, layers onto any material)]
        [Toggle(_WEATHERING_ON)] _WeatheringOn ("Enable Weathering", Float) = 0
        _RustColor  ("Weathering Color", Color)            = (0.42, 0.21, 0.10, 1)
        _RustAmount ("Weathering Coverage", Range(0,1))     = 0.35
        _RustScale  ("Weathering Patch Scale", Range(1,50)) = 12

        [Header(Emission  separate from SelfLit  texturemasked)]
        [Toggle(_EMISSION_ON)] _EmissionOn ("Enable Emission Map", Float) = 0
        [NoScaleOffset] _EmissionMap    ("Emission Mask",  2D)        = "black" {}
        _EmissionColor                  ("Emission Color", Color)     = (1,0.82,0.5,1)
        _EmissionIntensity              ("Intensity",      Range(0,8)) = 0.0

        [Header(Options)]
        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clip", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Window Transparency)]
        [Toggle(_TRANSPARENT_ON)] _TransparentOn ("Enable Transparency (Windows)", Float) = 0
        _WindowTint    ("Window Tint",    Color)           = (0.02, 0.02, 0.03, 1)
        _WindowOpacity ("Window Opacity", Range(0,1))       = 0.85
        _TintDarkness  ("Tint Darkness (0=clear glass, 1=dark tint)", Range(0,1)) = 0.92
        _ReflectionStr ("Reflection Strength", Range(0,2))  = 1.6
        _EdgeColor     ("Edge/Rim Color", Color)            = (0.85, 0.9, 1.0, 0.6)
        _FresnelPower  ("Edge Fresnel (glass rim)", Range(0.1,8)) = 3.0
        _FresnelStr    ("Edge Fresnel Strength",    Range(0,1)) = 0.25
        [Toggle(_SCREEN_SPACE_REFLECTION)] _ScreenSpaceReflectionOn ("Use Screen-Space Reflection (live scene, not probe/skybox)", Float) = 0
        _SSRParallax   ("SSR Sample Offset Scale", Range(0,0.2)) = 0.05
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend (auto)", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend (auto)", Float) = 0
        [Enum(Off,0,On,1)] _ZWrite ("ZWrite (auto)", Float) = 1

        [Header(Interior Light  Windows)]
        [Toggle(_INTERIOR_LIGHT_ON)] _InteriorLightOn ("Enable Interior Glow", Float) = 0
        _InteriorLightColor     ("Interior Light Color", Color)          = (1.0, 0.85, 0.55, 1)
        _InteriorLightIntensity ("Interior Light Intensity", Range(0,4)) = 1.2
        _InteriorFlicker        ("Flicker Amount (0=steady)", Range(0,1)) = 0.0
        _InteriorFlickerSpeed   ("Flicker Speed", Range(0,20)) = 6.0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue"          = "Geometry"
        }
        LOD 200

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            // [FIX] Only ZWrite is wired to a real material property here.
            // Blend stays hardcoded to SrcAlpha/OneMinusSrcAlpha -- that was
            // already correct and is what every window material actually
            // relies on for its look; the material's own _SrcBlend/_DstBlend
            // values are unused leftovers (stuck at One/Zero) and switching
            // the pass to read them made windows render opaque. ZWrite On was
            // the actual bug: it ignored the shader's own exposed _ZWrite
            // property, so a transparent window always wrote depth and
            // occluded anything drawn behind it (e.g. RouteGuideArrows).
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite [_ZWrite]

            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag
            #pragma target   4.5

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _EMISSION_ON
            #pragma shader_feature_local _TRANSPARENT_ON
            #pragma shader_feature_local _INTERIOR_LIGHT_ON
            #pragma shader_feature_local _SCREEN_SPACE_REFLECTION
            #pragma shader_feature_local _WEATHERING_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"

            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);
            TEXTURE2D(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);

            // ── Custom Light Array Globals ────────────────────────────────────
            int _CustomLightCount;
            float4 _CustomLightPositions[16];
            float4 _CustomLightColors[16];

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                half4  _DarkColor;
                half4  _MidColor;
                half   _MidThreshold;
                half   _LitThreshold;
                half   _AmbientStr;
                half   _LightColorInfluence;
                half   _Smoothness;
                half   _Metallic;
                half4  _SpecularColor;
                half   _SpecularIntensity;
                half   _ClearcoatStr;
                half   _SelfLit;
                half4  _RustColor;
                half   _RustAmount;
                half   _RustScale;
                half4  _EmissionColor;
                half   _EmissionIntensity;
                half   _Cutoff;
                half4  _WindowTint;
                half   _WindowOpacity;
                half   _TintDarkness;
                half   _ReflectionStr;
                half4  _EdgeColor;
                half   _FresnelPower;
                half   _FresnelStr;
                half   _SSRParallax;
                half4  _InteriorLightColor;
                half   _InteriorLightIntensity;
                half   _InteriorFlicker;
                half   _InteriorFlickerSpeed;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float  fogFactor  : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.fogFactor  = ComputeFogFactor(OUT.positionCS.z);
                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float3 N = normalize(IN.normalWS);
                float3 V = normalize(GetCameraPositionWS() - IN.positionWS);

                #if defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #else
                    float4 shadowCoord = float4(0,0,0,0);
                #endif
                Light mainLight = GetMainLight(shadowCoord);

                half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 albedo     = baseSample.rgb * _BaseColor.rgb;
                #if _ALPHATEST_ON
                    clip(baseSample.a * _BaseColor.a - _Cutoff);
                #endif

                half weatherMask = 0.0h;
                #if _WEATHERING_ON
                {
                    half wNoise = frac(sin(dot(floor(IN.positionWS.xyz * _RustScale), half3(12.9898h, 78.233h, 37.719h))) * 43758.5453h);
                    weatherMask = step(1.0h - _RustAmount, wNoise);
                    albedo = lerp(albedo, _RustColor.rgb, weatherMask);
                }
                #endif

                half NdotL       = dot(N, mainLight.direction);
                half halfLambert = saturate(NdotL * 0.5h + 0.5h);

                half toMid = step(_MidThreshold, halfLambert);
                half toLit = step(_LitThreshold, halfLambert);

                half3 tintedDark = lerp(_DarkColor.rgb, _DarkColor.rgb * mainLight.color.rgb, _LightColorInfluence);
                half3 tintedMid  = lerp(_MidColor.rgb,  _MidColor.rgb  * mainLight.color.rgb, _LightColorInfluence);

                half3 darkBand = albedo * tintedDark;
                half3 midBand  = albedo * tintedMid;
                half3 litBand  = albedo * mainLight.color.rgb;

                half3 celColor = lerp(darkBand, lerp(midBand, litBand, toLit), toMid);

                half  shadowStep = step(0.5h, mainLight.shadowAttenuation);
                half3 color      = lerp(darkBand, celColor, shadowStep);

                half3 ambient = SampleSH(N) * albedo * _AmbientStr;
                color = max(color, ambient);

                half localSmoothness = _Smoothness * (1.0h - weatherMask * 0.85h);
                half localMetallic   = _Metallic   * (1.0h - weatherMask);

                float3 H         = normalize(mainLight.direction + V);
                half   NdotH     = saturate(dot(N, H));
                half   specExp   = lerp(6.0h, 300.0h, localSmoothness * localSmoothness);
                half   specPow   = pow(max(NdotH, 1e-4h), specExp);
                half   specCut   = lerp(0.999h, 0.6h, localSmoothness);
                half   specMask  = step(specCut, specPow) * step(0.0h, NdotL) * shadowStep;

                half3 specTint = lerp(_SpecularColor.rgb, albedo, localMetallic);
                color += specMask * specTint * _SpecularIntensity * (0.5h + localMetallic);

                if (_ClearcoatStr > 0.001h)
                {
                    float3 ccR        = reflect(-V, N);
                    float2 ccScreenUV = IN.positionCS.xy / _ScaledScreenParams.xy;
                    half3  ccRefl     = GlossyEnvironmentReflection(ccR, IN.positionWS, 0.0h, 1.0h, ccScreenUV);
                    half   ccFresnel  = pow(1.0h - saturate(dot(N, V)), 2.0h);
                    color = lerp(color, ccRefl, ccFresnel * _ClearcoatStr * (1.0h - weatherMask));
                }

                if (_SelfLit > 0.001h)
                {
                    color += albedo * _SelfLit * 2.0h;
                }

                // ── Additional Lights (Forward, Forward+, and Deferred+ compatible) ──
                // Raw for-loops over GetAdditionalLight(i, ...) only work correctly
                // under classic Forward -- GetAdditionalLightsCount() always returns 0
                // under Forward+, and a manual loop doesn't consult the per-tile/cluster
                // light list Forward+ actually uses. LIGHT_LOOP_BEGIN/END expand to the
                // correct implementation for whichever rendering path is active.
                #if defined(_ADDITIONAL_LIGHTS) || defined(_CLUSTER_LIGHT_LOOP)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.positionWS;
                    inputData.normalWS   = N;
                    inputData.positionCS = IN.positionCS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                    uint pixelLightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light addLight  = GetAdditionalLight(lightIndex, IN.positionWS, half4(1,1,1,1));
                        half  addNdotL  = saturate(dot(N, addLight.direction));
                        half  addAtten  = addLight.distanceAttenuation * addLight.shadowAttenuation;
                        // Hard toon step instead of a soft gradient, so additional lights
                        // snap into a lit/unlit band the same way the main light does
                        // rather than glowing continuously outward from the source.
                        half  addBand   = step(0.15h, addNdotL * addAtten);
                        half3 addTinted = lerp(albedo, albedo * addLight.color.rgb, _LightColorInfluence);
                        color += addTinted * addLight.color.rgb * addBand * 0.5h;
                    LIGHT_LOOP_END
                }
                #endif

                // ── Custom Light Array Loop (Bypasses URP Tile Culling) ─────────────
                for (int cIdx = 0; cIdx < _CustomLightCount; ++cIdx)
                {
                    float3 cPos   = _CustomLightPositions[cIdx].xyz;
                    float  cRange = _CustomLightPositions[cIdx].w;
                    float3 cColor = _CustomLightColors[cIdx].rgb;

                    if (cRange > 0.001h)
                    {
                        float3 cLightVec = cPos - IN.positionWS;
                        float  dist      = length(cLightVec);
                        float3 cDir      = normalize(cLightVec);

                        float  atten     = saturate(1.0h - (dist / max(cRange, 0.0001h)));
                        atten *= atten;

                        half   cNdotL    = saturate(dot(N, cDir));
                        half   cBand     = smoothstep(0.05h, 0.3h, cNdotL * atten);

                        color += albedo * cColor * cBand * 0.5h;
                    }
                }

                #if _EMISSION_ON
                {
                    half3 emitMask = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, IN.uv).rgb;
                    color += emitMask * _EmissionColor.rgb * _EmissionIntensity;
                }
                #endif

                color = MixFog(color, IN.fogFactor);

                half outAlpha = 1.0h;

                #if _TRANSPARENT_ON
                {
                    half fresnel = pow(1.0h - saturate(dot(N, V)), _FresnelPower) * _FresnelStr;

                    half3 tinted = lerp(color, color * _WindowTint.rgb * 2.0h, _TintDarkness);

                    float3 R          = reflect(-V, N);
                    float2 screenUV   = IN.positionCS.xy / _ScaledScreenParams.xy;
                    half3  reflColor;

                    #if _SCREEN_SPACE_REFLECTION
                        float2 reflOffset = R.xy * _SSRParallax;
                        reflColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV + reflOffset).rgb;
                    #else
                        reflColor = GlossyEnvironmentReflection(R, IN.positionWS, 0.0h, 1.0h, screenUV);
                    #endif

                    half   reflAmount = saturate(fresnel * _ReflectionStr * 0.35h + _ReflectionStr * 0.65h);
                    half3  reflected  = lerp(tinted, reflColor, reflAmount);

                    half3 withEdge = reflected + fresnel * _EdgeColor.rgb * _EdgeColor.a;

                    #if _INTERIOR_LIGHT_ON
                    {
                        half flicker = 1.0h;
                        if (_InteriorFlicker > 0.0h)
                        {
                            half n = frac(sin(dot(IN.positionWS.xz, half2(12.9898h, 78.233h))) * 43758.5453h);
                            flicker = 1.0h - _InteriorFlicker * 0.5h
                                    * (0.5h + 0.5h * sin(_Time.y * _InteriorFlickerSpeed + n * 6.283h));
                        }
                        // Weighted by (1 - reflAmount) so interior glow recedes behind
                        // exterior reflections at grazing angles, like real glass —
                        // instead of flatly washing every window regardless of angle.
                        withEdge += _InteriorLightColor.rgb * _InteriorLightIntensity * flicker * (1.0h - reflAmount);
                    }
                    #endif

                    color = withEdge;

                    outAlpha = saturate(_WindowOpacity
                                       + _TintDarkness * 0.2h
                                       + reflAmount * 0.25h
                                       #if _INTERIOR_LIGHT_ON
                                       + 0.15h
                                       #endif
                                       );
                }
                #endif

                color = saturate(color);

                return half4(color, outAlpha);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   ShadowVert
            #pragma fragment ShadowFrag
            #pragma target   4.5
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif

                float4 posCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDir));

                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, posCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, posCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.positionCS = posCS;
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target { return 0; }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}