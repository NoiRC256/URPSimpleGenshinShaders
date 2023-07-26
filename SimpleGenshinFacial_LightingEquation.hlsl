// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// This file is intented for you to edit and experiment with different lighting equation.
// Add or edit whatever code you want here

// #pragma once is a safe guard best practice in almost every .hlsl (need Unity2020 or up), 
// doing this can make sure your .hlsl's user can include this .hlsl anywhere anytime without producing any multi include conflict
#pragma once

float3x3 AngleAxis3x3(float angle, float3 axis);

half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // hide 3D feeling by ignoring all detail SH (leaving only the constant SH term)
    // we just want some average envi indirect color only
    half3 averageSH = SampleSH(0);

    // can prevent result becomes completely black if lightprobe was not baked 
    averageSH = max(_IndirectLightMinColor,averageSH);

    // occlusion (maximum 50% darken for indirect to prevent result becomes completely black)
    half indirectOcclusion = lerp(1, surfaceData.occlusion, 0.5);
    return averageSH * indirectOcclusion;
}

half3 CalculateFaceShadowMapShading(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
    half3 L = light.direction;
    half3 modifiedL = L;
    // Offset the received light direction by rotating around y axis.
    if(surfaceData.faceDirectionOffset != 0){
        modifiedL = mul(L, AngleAxis3x3(surfaceData.faceDirectionOffset, float3(0,1,0)));
    }

    // Get object directions relative to light direction.
    half3 Up = unity_ObjectToWorld._m01_m11_m21;
    half IsUpright = (Up.y - L.y) < 0 ? 1 : -1;
    half3 Forward = unity_ObjectToWorld._m02_m12_m22;
    half FdotL = dot(Forward.xz, modifiedL.xz) * IsUpright;
    half3 Right = unity_ObjectToWorld._m00_m10_m20;
    half RdotL = dot(Right.xz, modifiedL.xz) * IsUpright;

    // Choose original map L (light from left) or flipped map R (light from right).
    half faceShadowMap = RdotL > 0 ? surfaceData.faceShadowMapR.r : surfaceData.faceShadowMapL.r;

    // Calculate result.
    half normalizedFdotL = (surfaceData.flipFaceDirection >= 1 ? -1 : 1) * -0.5 * FdotL + 0.5;
    normalizedFdotL %= 1;
    half litOrShadow = step(normalizedFdotL , faceShadowMap);
    return litOrShadow;
}

// Most important part: lighting equation, edit it according to your needs, write whatever you want here, be creative!
// This function will be used by all direct lights (directional/point/spot)
half3 ShadeSingleLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 N = lightingData.normalWS;
    half3 L = light.direction;

    half NoL = dot(N,L);

    half lightAttenuation = 1;

    // light's distance & angle fade for point light & spot light (see GetAdditionalPerObjectLight(...) in Lighting.hlsl)
    // Lighting.hlsl -> https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
    half distanceAttenuation = min(4,light.distanceAttenuation); //clamp to prevent light over bright if point/spot light too close to vertex

    // N dot L
    // simplest 1 line cel shade, you can always replace this line by your own method!
    half litOrShadowArea = smoothstep(_CelShadeMidPoint-_CelShadeSoftness,_CelShadeMidPoint+_CelShadeSoftness, NoL);

    // occlusion
    litOrShadowArea *= surfaceData.occlusion;

    // face ignore celshade since it is usually very ugly using NoL method
    litOrShadowArea = _IsFace? lerp(0.5,1,litOrShadowArea) : litOrShadowArea;

    // dynamic face shadow map
    litOrShadowArea = _UseFaceShadowMap ? CalculateFaceShadowMapShading(surfaceData, lightingData, light) : litOrShadowArea;

    // light's shadow map
    litOrShadowArea *= lerp(1,light.shadowAttenuation,_ReceiveShadowMappingAmount);

    half combinedShadowArea = litOrShadowArea;
    
    half3 litOrShadowColor = lerp(_ShadowMapColor,1, combinedShadowArea);

    half3 lightAttenuationRGB = litOrShadowColor * distanceAttenuation;

    // saturate() light.color to prevent over bright
    // additional light reduce intensity since it is additive
    return saturate(light.color) * lightAttenuationRGB * (isAdditionalLight ? 0.25 : 1);
}

half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    half3 emissionResult = lerp(surfaceData.emission, surfaceData.emission * surfaceData.albedo, _EmissionMulByBaseColor); // optional mul albedo
    return emissionResult;
}

half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // [remember you can write anything here, this is just a simple tutorial method]
    // here we prevent light over bright,
    // while still want to preserve light color's hue
    half3 rawLightSum = max(indirectResult, mainLightResult + additionalLightSumResult); // pick the highest between indirect and direct light
    return surfaceData.albedo * rawLightSum + emissionResult;
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
