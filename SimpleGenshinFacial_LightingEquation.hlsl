// For more information, visit -> https://github.com/NoiRC256/UnityURPToonLitShaderExample
// Original shader -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// This file is intented for you to edit and experiment with different lighting equation.
// Add or edit whatever code you want here

// #ifndef XXX + #define XXX + #endif is a safe guard best practice in almost every .hlsl, 
// doing this can make sure your .hlsl's user can include this .hlsl anywhere anytime without producing any multi include conflict
#ifndef SimpleGenshinFacial_LightingEquation_Include
    #define SimpleGenshinFacial_LightingEquation_Include

    half3 InternalShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
    {
        // hide 3D feeling by ignoring all detail SH
        // SH 1 (only use this)
        // SH 234 (ignored)
        // SH 56789 (ignored)
        // we just want to tint some average envi color only
        half3 averageSH = SampleSH(0);

        // occlusion
        // separated control for indirect occlusion
        half indirectOcclusion = lerp(1, surfaceData.occlusion, _OcclusionIndirectStrength);
        half3 indirectLight = averageSH * (_IndirectLightMultiplier * indirectOcclusion);
        return max(indirectLight, _IndirectLightMinColor); // can prevent completely black if lightprobe was not baked
    }

    // Rotation with angle (in radians) and axis
    float3x3 AngleAxis3x3(float angle, float3 axis)
    {
        float c, s;
        sincos(angle, s, c);

        float t = 1 - c;
        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

        return float3x3(
        t * x * x + c,      t * x * y - s * z,  t * x * z + s * y,
        t * x * y + s * z,  t * y * y + c,      t * y * z - s * x,
        t * x * z - s * y,  t * y * z + s * x,  t * z * z + c
        );
    }

    half3 InternalShadeMainLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
    {
        half3 L = light.direction;
        half3 modifiedL = L;
        // Offset the received light direction by rotating around y axis.
        if(surfaceData._faceDirectionOffset != 0){
            modifiedL = mul(L, AngleAxis3x3(surfaceData._faceDirectionOffset, float3(0,1,0)));
        }

        // Get object directions relative to light direction.
        half3 Up = unity_ObjectToWorld._m01_m11_m21;
        half IsUpright = (Up.y - L.y) < 0 ? 1 : -1;
        half3 Forward = unity_ObjectToWorld._m02_m12_m22;
        half FdotL = dot(Forward.xz, modifiedL.xz) * IsUpright;
        half3 Right = unity_ObjectToWorld._m00_m10_m20;
        half RdotL = dot(Right.xz, modifiedL.xz) * IsUpright;

        // Choose original lightmap L (light from left) or flipped lightmap R (light from right).
        half LightMap = RdotL > 0 ? surfaceData._lightMapR.r : surfaceData._lightMapL.r;

        // Calculate result.
        half normalizedFdotL = (surfaceData._reverseFaceDirection >= 1 ? -1 : 1) * -0.5 * FdotL + 0.5;
        normalizedFdotL %= 1;
        half litOrShadow = step(normalizedFdotL , LightMap);

        return light.color * lerp(litOrShadow, 1, step(surfaceData._useLightMap, 0));
    }

    half3 InternalShadeAdditionalLights(ToonSurfaceData surfaceData,
    ToonLightingData lightingData, Light light, bool isAdditionalLight)
    {
        return 0; //write your own equation here ! (see ShadeSingleLightDefaultMethod(...))
    }

    half3 InternalShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
    {
        half3 N = lightingData.normalWS;
        half3 L = light.direction;
        half3 V = lightingData.viewDirectionWS;
        half3 H = normalize(L + V);

        half3 shadowColor = surfaceData._shadowColor;

        half3 emission = surfaceData.emission;
        half NoL = dot(N, L);

        half3 emissionResult = lerp(emission, emission * surfaceData.albedo, _EmissionMulByBaseColor); // optional mul albedo
        return emissionResult;
    }

    // Composite all shading results.
    half3 InternalCompositeLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult,
    ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
    {
        half3 shadowColor = light.color * lerp(1 * surfaceData._shadowColor, 1, mainLightResult);
        half3 rawLightSum = max(indirectResult * shadowColor, mainLightResult + additionalLightSumResult); // pick the highest between indirect and direct light
        half lightLuminance = Luminance(rawLightSum);

        half3 finalLightMulResult = rawLightSum / max(1, lightLuminance / max(1, log(lightLuminance))); // allow controlled over bright using log
        return surfaceData.albedo * finalLightMulResult + emissionResult;
    }


    // We split lighting functions into: 
    // - indirect
    // - main light 
    // - additional lights (point lights/spot lights)
    // - emission

    half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
    {
        return InternalShadeGI(surfaceData, lightingData);
    }

    half3 ShadeMainLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
    {
        return InternalShadeMainLight(surfaceData, lightingData, light, false);
    }

    half3 ShadeAdditionalLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
    {
        return InternalShadeAdditionalLights(surfaceData, lightingData, light, true);
    }

    half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
    {
        return InternalShadeEmission(surfaceData, lightingData, light, false);
    }

    half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult,
    ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
    {
        return InternalCompositeLightResults(indirectResult, mainLightResult, additionalLightSumResult, emissionResult, surfaceData, lightingData, light);
    }

#endif
