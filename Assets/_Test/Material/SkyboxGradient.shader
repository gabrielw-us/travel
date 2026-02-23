Shader "Custom/SkyboxGradient"
{
    Properties
    {
        _TopColor ("Top Color", Color) = (0.4, 0.6, 0.9, 1)
        _BottomColor ("Bottom Color", Color) = (0.9, 0.9, 1, 1)
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Opaque" }
        Cull Off ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _TopColor;
            fixed4 _BottomColor;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 dir : TEXCOORD0;
            };

            v2f vert (float4 vertex : POSITION)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(vertex);
                o.dir = normalize(mul(unity_ObjectToWorld, vertex).xyz);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float t = saturate(i.dir.y * 0.5 + 0.5); // Remap from [-1,1] to [0,1]
                return lerp(_BottomColor, _TopColor, t);
            }
            ENDCG
        }
    }
    FallBack "RenderFX/Skybox"
}
