Shader "Simple Toon/SToon Outline"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        [Header(Colorize)][Space(5)]
        _Color      ("Color",      COLOR)         = (1,1,1,1)
        [HideInInspector] _ColIntense ("Intensity",   Range(0,3))   = 1
        [HideInInspector] _ColBright  ("Brightness",  Range(-1,1))  = 0
        _AmbientCol ("Ambient",    Range(0,1))    = 0

        [Header(Detail)][Space(5)]
        [Toggle] _Segmented ("Segmented",  Float)       = 1
        _Steps     ("Steps",      Range(1,25))   = 3
        _StpSmooth ("Smoothness", Range(0,1))    = 0
        _Offset    ("Lit Offset", Range(-1,1.1)) = 0

        [Header(Light)][Space(5)]
        [Toggle] _Clipped ("Clipped",    Float)      = 0
        _MinLight ("Min Light",  Range(0,1))  = 0
        _MaxLight ("Max Light",  Range(0,1))  = 1
        _Lumin    ("Luminocity", Range(0,2))  = 0

        [Header(Outline)][Space(5)]
        _OtlColor ("Color", COLOR)         = (0,0,0,1)
        _OtlWidth ("Width", Range(0,5))    = 1

        [Header(Shine)][Space(5)]
        [HDR] _ShnColor  ("Color",      COLOR)        = (1,1,0,1)
        [Toggle] _ShnOverlap ("Overlap", Float)       = 0
        _ShnIntense ("Intensity",  Range(0,1))    = 0
        _ShnRange   ("Range",      Range(0,1))    = 0.15
        _ShnSmooth  ("Smoothness", Range(0,1))    = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // ── Outline pass (back-face extrusion, renders first) ──────────────
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // Extrude along object-space normal, then transform to clip
                float3 extruded = IN.positionOS.xyz + normalize(IN.normalOS) * _OtlWidth * 0.008;
                OUT.positionHCS = TransformObjectToHClip(extruded);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // Clip outline when width is 0
                clip(_OtlWidth - 0.0001);
                return _OtlColor;
            }
            ENDHLSL
        }

        // ── Forward Lit ────────────────────────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "STCore.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 viewDirWS   : TEXCOORD2;
                float3 positionWS  : TEXCOORD3;
                float  fogFactor   : TEXCOORD4;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   nrmInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = nrmInputs.normalWS;
                OUT.viewDirWS   = GetWorldSpaceViewDir(posInputs.positionWS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.fogFactor   = ComputeFogFactor(posInputs.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 normal  = normalize(IN.normalWS);
                float3 viewDir = normalize(IN.viewDirWS);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light  mainLight   = GetMainLight(shadowCoord);

                float3 lightDir = normalize(mainLight.direction);
                float3 halfVec  = normalize(lightDir + viewDir);

                float NdotL = dot(normal, lightDir);
                float NdotH = dot(normal, halfVec);
                float VdotN = dot(viewDir, normal);

                float atten    = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                float maxAtten = 1.0;
                float toon     = Toon(NdotL, atten, maxAtten);

                float4 texcol  = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                float4 litcol  = ColorBlend(_Color, float4(mainLight.color, 1), _AmbientCol);
                float4 albedo  = texcol * litcol * _ColIntense + _ColBright;

                float4 shadecol = float4(0, 0, 0, 1);
                float4 blendCol = ColorBlend(shadecol, albedo, toon);
                float4 postCol  = PostEffects(blendCol, toon, atten, maxAtten, NdotL, NdotH, VdotN, 0);

                #ifdef _ADDITIONAL_LIGHTS
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, IN.positionWS);
                    float addNdotL = dot(normal, normalize(addLight.direction));
                    float addAtten = addLight.shadowAttenuation * addLight.distanceAttenuation;
                    float addToon  = Toon(addNdotL, addAtten, maxAtten);
                    float4 addCol  = ColorBlend(shadecol, albedo, addToon) * float4(addLight.color, 1);
                    postCol = max(postCol, addCol);
                }
                #endif

                postCol.rgb = MixFog(postCol.rgb, IN.fogFactor);
                postCol.a   = 1.0;
                return postCol;
            }
            ENDHLSL
        }

        // ── Shadow Caster ──────────────────────────────────────────────────
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0

            HLSLPROGRAM
            #pragma vertex   ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // ── Depth Only ─────────────────────────────────────────────────────
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R

            HLSLPROGRAM
            #pragma vertex   DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
