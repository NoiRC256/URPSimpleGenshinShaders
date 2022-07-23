// For more information, visit -> https://github.com/NoiRC256/UnityURPToonLitShaderExample
// Original shader -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// This file is intented for you to edit and experiment with different lighting equation.
// Add or edit whatever code you want here

// #ifndef XXX + #define XXX + #endif is a safe guard best practice in almost every .hlsl, 
// doing this can make sure your .hlsl's user can include this .hlsl anywhere anytime without producing any multi include conflict
#ifndef SimpleGenshinFacial_LightingEquation_Include
#define SimpleGenshinFacial_LightingEquation_Include

// LEGACY METHODS
/*
half3 ShadeGIDefaultMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData)
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

half3 CustomFaceShade(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight) {

	half3 N = lightingData.normalWS;
	half3 L = light.direction;
	half3 V = lightingData.viewDirectionWS;
	half3 H = normalize(L + V);
	half3 shadowColor = surfaceData._shadowColor;

	half NoL = dot(N, L);

	// ====== Module Start: Genshin style facial shading ======

	// Get forward and right vectors from rotation matrix;
	float3 ForwardVector = unity_ObjectToWorld._m02_m12_m22;
	float3 RightVector = unity_ObjectToWorld._m00_m10_m20;

	// Normalize light direction in relation to forward and right vectors;
	float FrontLight = dot(normalize(ForwardVector.xz), normalize(L.xz));
	float RightLight = dot(normalize(RightVector.xz), normalize(L.xz));

	RightLight = -(acos(RightLight) / 3.14159265 - 0.5) * 2; // Shadow coverage fix for smoother transition -> https://zhuanlan.zhihu.com/p/279334552;

	// Use r value from the original lightmapileft part in shadow) or flipped lightmap (right part in shadow) depending on normalized light direction;
	float LightMap = RightLight > 0 ? surfaceData._lightMapR.r : surfaceData._lightMapL.r;

	// This controls how we distribute the speed at which we scroll across the lightmap based on normalized light direction;
	// Higher values = faster transitions when facing light and slower transitions when facing away from light, lower values = opposite;
	float dirThreshold = 0.1;

	// If facing light, use right-normalized light direction with dirThreshold. 
	// If facing away from light, use front-normalized light direction with (1 - dirThreshold) and a corresponding translation...
	// ...to ensure smooth transition at 180 degrees (where front-normalized light direction == 0).
	float lightAttenuation_temp = (FrontLight > 0) ?
		min((LightMap > dirThreshold * RightLight), (LightMap > dirThreshold * -RightLight)) :
		min((LightMap > (1 - dirThreshold * 2)* FrontLight - dirThreshold), (LightMap > (1 - dirThreshold * 2)* -FrontLight + dirThreshold));

	// [REDUNDANT] Compensate for translation when facing away from light;
	//lightAttenuation_temp += (FrontLight < -0.9) ? (min((LightMap > 1 * FrontLight), (LightMap > 1 * -FrontLight))) : 0;

	// ====== Module End ======



	float lightAttenuation = surfaceData._useLightMap ? lightAttenuation_temp : 1;



	return light.color * lightAttenuation;
}

// Most important part: lighting equation, edit it according to your needs, write whatever you want here, be creative!
// this function will be used by all direct lights (directional/point/spot)
half3 ShadeSingleLightDefaultMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 N = lightingData.normalWS;
    half3 L = light.direction;
    half3 V = lightingData.viewDirectionWS;
    half3 H = normalize(L+V);

    half NoL = dot(N,L);

	// Replace original initialization with custom face shading result;
	// float lightAttenuation = 1f;
	float lightAttenuation = CustomFaceShade(surfaceData, lightingData, light, isAdditionalLight);


    // light's shadow map. If you prefer hard shadow, you can smoothstep() light.shadowAttenuation to make it sharp.
    lightAttenuation *= lerp(1,light.shadowAttenuation,_ReceiveShadowMappingAmount);

    // light's distance & angle fade for point light & spot light (see GetAdditionalPerObjectLight() in Lighting.hlsl)
    // Lighting.hlsl -> https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
    lightAttenuation *= min(4,light.distanceAttenuation); //prevent light over bright if point/spot light too close to vertex

    // N dot L
    // simplest 1 line cel shade, you can always replace this line by your own better method !
    half celShadeResult = smoothstep(_CelShadeMidPoint-_CelShadeSoftness,_CelShadeMidPoint+_CelShadeSoftness, NoL);

    // don't want direct lighting's cel shade effect looks too strong? set ignoreValue to a higher value
    lightAttenuation *= lerp(celShadeResult,1, isAdditionalLight? _AdditionalLightIgnoreCelShade : _MainLightIgnoreCelShade);

    // don't want direct lighting becomes too bright for toon lit characters? set this value to a lower value 
    lightAttenuation *= _DirectLightMultiplier;

    // occlusion
    // separated control for direct occlusion
    half directOcclusion = lerp(1, surfaceData.occlusion, _OcclusionDirectStrength);
    lightAttenuation *= directOcclusion;

    return light.color * lightAttenuation;
}

half3 CalculateRamp(half ndlWrapped)
{
#if defined(TCP2_RAMPTEXT)
	half3 ramp = tex2D(_Ramp, _RampOffset + ((ndlWrapped.xx - 0.5) * _RampScale) + 0.5).rgb;
#elif defined(TCP2_RAMP_BANDS) || defined(TCP2_RAMP_BANDS_CRISP)
	half bands = _RampBands;

	half rampThreshold = _RampThreshold;
	half rampSmooth = _RampSmoothing * 0.5;
	half x = smoothstep(rampThreshold - rampSmooth, rampThreshold + rampSmooth, ndlWrapped);

#if defined(TCP2_RAMP_BANDS_CRISP)
	half bandsSmooth = fwidth(ndlWrapped) * (2.0 + bands);
#else
	half bandsSmooth = _RampBandsSmoothing * 0.5;
#endif
	half3 ramp = saturate((smoothstep(0.5 - bandsSmooth, 0.5 + bandsSmooth, frac(x * bands)) + floor(x * bands)) / bands).xxx;
#else
#if defined(TCP2_RAMP_CRISP)
	half rampSmooth = fwidth(ndlWrapped) * 0.5;
#else
	half rampSmooth = 0.1 * 0.5;
#endif
	half rampThreshold = 0.75;
	half3 ramp = smoothstep(rampThreshold - rampSmooth, rampThreshold + rampSmooth, ndlWrapped).xxx;
#endif
	return ramp;
}

half3 ShadeEmissionDefaultMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
	half3 N = lightingData.normalWS;
	half3 L = light.direction;
	half3 V = lightingData.viewDirectionWS;
	half3 H = normalize(L + V);

	half3 shadowColor = surfaceData._shadowColor;
	half useRimLight = surfaceData._useRimLight;
	half4 rimColor = surfaceData._rimColor;
	half3 rimMin = surfaceData._rimMin;
	half3 rimMax = surfaceData._rimMax;

	half3 emission = surfaceData.emission;
	half NoL = dot(N, L);

    half3 emissionResult = lerp(emission, emission * surfaceData.albedo, _EmissionMulByBaseColor); // optional mul albedo
    return emissionResult;
}

half3 CompositeAllLightResultsDefaultMethod(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // [remember you can write anything here, this is just a simple tutorial method]
    // here we prevent light over bright,
    // while still want to preserve light color's hue

	half3 shadowColor = light.color * lerp(1 * surfaceData._shadowColor, 1, faceShadowMask);
    half3 rawLightSum = max(indirectResult*shadowColor, mainLightResult + additionalLightSumResult); // pick the highest between indirect and direct light
    half lightLuminance = Luminance(rawLightSum);

    half3 finalLightMulResult = rawLightSum / max(1,lightLuminance / max(1,log(lightLuminance))); // allow controlled over bright using log
    return surfaceData.albedo * finalLightMulResult + emissionResult;

}
*/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Implement your own lighting equation here! 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

half3 ShadeGIMyMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData)
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
half3 ShadeMainLightMyMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
	half3 N = lightingData.normalWS;
	half3 L = light.direction;
	half3 V = lightingData.viewDirectionWS;
	half3 H = normalize(L + V);
	half3 shadowColor = surfaceData._shadowColor;

	half NoL = dot(N, L);

	// Genshin Style Face Light Map Shading.

	// Get forward and right vectors from rotation matrix;
	float3 ForwardVector = unity_ObjectToWorld._m02_m12_m22;
	float3 RightVector = unity_ObjectToWorld._m00_m10_m20;

	// Normalize light direction relative to forward and right vectors;
	float ForwardLight = dot(normalize(ForwardVector.xz), normalize(L.xz));
	float RightLight = dot(normalize(RightVector.xz), normalize(L.xz));

	// Shadow coverage fix for smoother transition.
    // https://zhuanlan.zhihu.com/p/279334552.
	RightLight = -(acos(RightLight) / 3.14159265 - 0.5) * 2;

	// Use r value from the original lightmap (left part in shadow) or flipped lightmap (right part in shadow) based on normalized light direction;
	float LightMap = lerp(surfaceData._lightMapR.r, surfaceData._lightMapL.r, step(RightLight, 0));

	// Apply lightmap.
    float lightMapAtten = lerp(
    min((LightMap > RightLight), (LightMap > -RightLight)),
    min((LightMap < RightLight), (LightMap < -RightLight)),
    step(ForwardLight, 0));

    float lightAttenuation = lerp(lightMapAtten, 1, step(surfaceData._useLightMap, 0));

	return light.color * lightAttenuation;
}
half3 ShadeAllAdditionalLightsMyMethod(ToonSurfaceData surfaceData, 
	ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    return 0; //write your own equation here ! (see ShadeSingleLightDefaultMethod(...))
}
half3 ShadeEmissionMyMethod(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
	half3 N = lightingData.normalWS;
	half3 L = light.direction;
	half3 V = lightingData.viewDirectionWS;
	half3 H = normalize(L + V);

	half3 shadowColor = surfaceData._shadowColor;
	half useRimLight = surfaceData._useRimLight;
	half4 rimColor = surfaceData._rimColor;
	half3 rimMin = surfaceData._rimMin;
	half3 rimMax = surfaceData._rimMax;

	half3 emission = surfaceData.emission;
	half NoL = dot(N, L);

	half3 emissionResult = lerp(emission, emission * surfaceData.albedo, _EmissionMulByBaseColor); // optional mul albedo
	return emissionResult;
}
half3 CompositeAllLightResultsMyMethod(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, 
	ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	half3 shadowColor = light.color * lerp(1 * surfaceData._shadowColor, 1, mainLightResult);
	half3 rawLightSum = max(indirectResult * shadowColor, mainLightResult + additionalLightSumResult); // pick the highest between indirect and direct light
	half lightLuminance = Luminance(rawLightSum);

	half3 finalLightMulResult = rawLightSum / max(1, lightLuminance / max(1, log(lightLuminance))); // allow controlled over bright using log
	return surfaceData.albedo * finalLightMulResult + emissionResult;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Once you have implemented an equation in the above section, switch to use your own lighting equation in below section!
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// We split lighting functions into: 
// - indirect
// - main light 
// - additional lights (point lights/spot lights)
// - emission

half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
	return ShadeGIMyMethod(surfaceData, lightingData);
}
half3 ShadeMainLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	return ShadeMainLightMyMethod(surfaceData, lightingData, light, false);
}
half3 ShadeAdditionalLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	return ShadeAllAdditionalLightsMyMethod(surfaceData, lightingData, light, true);
}
half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	return ShadeEmissionMyMethod(surfaceData, lightingData, light, false);
}
half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, 
	ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	return CompositeAllLightResultsMyMethod(indirectResult, mainLightResult, additionalLightSumResult, emissionResult, surfaceData, lightingData, light);
}

#endif
