Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
        
        half3 wTangent : TEXCOORD1;
        half3 wBitangent : TEXCOORD2;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = wNormal;
        
        // compute bitangent from cross product of normal and tangent and output it
        half tangentSign = tangent.w * unity_WorldTransformParams.w;
        o.wTangent = wTangent;
        o.wBitangent = cross(wNormal, wTangent) * tangentSign;
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
        half3x3 inv_tbn = half3x3(i.wTangent, i.wBitangent, i.worldSurfaceNormal);
        half3x3 tbn = transpose(inv_tbn);
        float3 tgViewDir = normalize(mul(inv_tbn, worldViewDir));

#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping
        float h = tex2D(_HeightMap, uv).z;
        h = h * _MaxHeight;
        float2 offset = h * tgViewDir.xy / (tgViewDir.z);
        uv += offset;
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        // Change UV according to Parallax Occclusion Mapping
        float tgABS =  length(tgViewDir.xy);
        if (tgABS != 0) {
            float3 tgStep = tgViewDir * _StepLength / tgABS;
            float3 pointB = float3(uv.x, uv.y, _MaxHeight);
            float3 pointA = pointB + tgStep;
            [unroll(150)] for (int t = 0; t < _MaxStepCount; ++t) {
                float h = tex2D(_HeightMap, pointA.xy).z * _MaxHeight;
                if (h <= pointA.z) {
                    pointB = pointA;
                    pointA += tgStep;
                }
            }
            float hA = abs(tex2D(_HeightMap, pointA.xy).z * _MaxHeight - pointA.z);
            float hB = abs(pointB.z - tex2D(_HeightMap, pointB.xy).z * _MaxHeight);
            uv = lerp(pointA.xy, pointB.xy, hA / (hA + hB));
            // uv = pointA.xy;
        }
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        // Implement Normal Mapping
        half3 tnormal = UnpackNormal(tex2D(_NormalMap, uv));
        // half3 actualNormal = tnormal.x * i.wTangent + tnormal.y * i.wBitangent + tnormal.z * normal;
        half3 actualNormal =  mul(tbn, tnormal);

        normal = actualNormal;
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}