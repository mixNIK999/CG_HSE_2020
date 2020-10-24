Shader "0_Custom/Cubemap"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0, 0, 0, 1)
        _Roughness ("Roughness", Range(0.03, 1)) = 1
        _Cube ("Cubemap", CUBE) = "" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            
            #define EPS 1e-7

            struct appdata
            {
                float4 vertex : POSITION;
                fixed3 normal : NORMAL;
            };

            struct v2f
            {
                float4 clip : SV_POSITION;
                float4 pos : TEXCOORD1;
                fixed3 normal : NORMAL;
            };

            float4 _BaseColor;
            float _Roughness;
            
            samplerCUBE _Cube;
            half4 _Cube_HDR;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.clip = UnityObjectToClipPos(v.vertex);
                o.pos = mul(UNITY_MATRIX_M, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            uint Hash(uint s)
            {
                s ^= 2747636419u;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                return s;
            }
            
            float Random(uint seed)
            {
                return float(Hash(seed)) / 4294967295.0; // 2^32-1
            }
            
            float3 SampleColor(float3 direction)
            {   
                half4 tex = texCUBE(_Cube, direction);
//                half4 tex = texCUBElod(_Cube, float4(direction, 0));
                return DecodeHDR(tex, _Cube_HDR).rgb;
            }
            
            float Sqr(float x)
            {
                return x * x;
            }
            
            // Calculated according to NDF of Cook-Torrance
            float GetSpecularBRDF(float3 viewDir, float3 lightDir, float3 normalDir)
            {
                float3 halfwayVector = normalize(viewDir + lightDir);               
                
                float a = Sqr(_Roughness);
                float a2 = Sqr(a);
                float NDotH2 = Sqr(dot(normalDir, halfwayVector));
                
                return a2 / (UNITY_PI * Sqr(NDotH2 * (a2 - 1) + 1));
            }

            float3 GetRandomVecOnSphere(int seed)
            {
                float alpha = Random(2 * seed) * 2 * UNITY_PI;
                float cos_alpha = cos(alpha);
                float sin_alpha = sin(alpha);
                
                float cos_theta = 2 * Random(2 * seed + 1) - 1;
                float sin_theta = sqrt(1 - Sqr(cos_theta));
          
                return float3(sin_theta * cos_alpha, sin_theta * sin_alpha, cos_theta);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 normal = normalize(i.normal);
                
                float3 viewDirection = normalize(_WorldSpaceCameraPos - i.pos.xyz);
                
                // Replace this specular calculation by Montecarlo.
                // Normalize the BRDF in such a way, that integral over a hemysphere of (BRDF * dot(normal, w')) == 1
                // TIP: use Random(i) to get a pseudo-random value.

                int N = 30000;
//                float3 viewRefl = reflect(-viewDirection.xyz, normal);
//                float3 specular = SampleColor(viewRefl);
                
                float brdf_normalizer = 0;
                float3 L = float3(0, 0, 0);
                for (int it = 0; it < N; it++)
                {
                    float3 random_vec = GetRandomVecOnSphere(it);
                    float cos_theta = dot(normal, random_vec);
                    if (cos_theta > 0)
                    {
                        float brdf = GetSpecularBRDF(viewDirection, random_vec, normal);
                        brdf_normalizer += brdf * cos_theta;
                        L += SampleColor(random_vec) * brdf * cos_theta;
                    }
                }
                L /= brdf_normalizer;
                
                return fixed4(L, 1);
//                return fixed4(specular, 1);
            }
            ENDCG
        }
    }
}
