// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// This file is intented for you to edit and experiment with different lighting equation.
// Add or edit whatever code you want here

// #ifndef XXX + #define XXX + #endif is a safe guard best practice in almost every .hlsl, 
// doing this can make sure your .hlsl's user can include this .hlsl anywhere anytime without producing any multi include conflict
#ifndef SimpleURPToonLitOutlineExample_LightingEquation_Include
#define SimpleURPToonLitOutlineExample_LightingEquation_Include

half3 ShadeGIDefaultMethod(ToonSurfaceData surfaceData, LightingData lightingData)
{
    // hide 3D feeling by ignore all detail SH
    // SH 1 (only use this)
    // SH 234 (ignored)
    // SH 56789 (ignored)
    // we just want to tint some average envi color only
    half3 averageSH = SampleSH(0);

    // extra separated control for indirect occlusion
    half indirectOcclusion = lerp(1, surfaceData.occlusion, _OcclusionIndirectStrength);
    half indirectLight = averageSH * _IndirectLightMultiplier * indirectOcclusion;
    return surfaceData.albedo * max(indirectLight, _IndirectLightMinColor);   
}
half3 CustomFaceShade(ToonSurfaceData surfaceData, LightingData lightingData, Light light, bool isAdditionalLight) 
{
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
	RightLight = -(acos(RightLight) / 3.14159265 - 0.5) * 2; // Shadow coverage fix for a smoother transition -> https://zhuanlan.zhihu.com/p/279334552;

	// Use r value from the original lightmapileft part in shadow) or flipped lightmap (right part in shadow) depending on normalized light direction;
	float LightMap = RightLight > 0 ? surfaceData._lightMapR.r : surfaceData._lightMapL.r;

	// This controls how we distribute the speed at which we scroll across the lightmap based on normalized light direction;
	// Higher values = faster transitions when facing light and slower transitions when facing away from light, lower values = vice-versa;
	float dirThreshold = 0.2;

	// If facing light, use right-normalized light direction with dirThreshold. 
	// If facing away from light, use front-normalized light direction with "1 - dirThreshold" and a corresponding translation...
	// ...to ensure contuity at 90 degrees (where front-normalized light direction == 0).

	// [WIP] simpler method
	//(FrontLight > 0) ?
	float lightAttenuation_temp = min((LightMap < FrontLight), (LightMap < -FrontLight));

	// [REDUNDANT] Compensate for translation when light comes from behind;
	//lightAttenuation_temp += (FrontLight < -0.9) ? (min((LightMap > 1 * FrontLight), (LightMap > 1 * -FrontLight))) : 0;

	// ====== Module End ======

	float lightAttenuation = surfaceData._useLightMap ? lightAttenuation_temp : 1;

	return lightAttenuation;
}

// Most important part: lighting equation, edit it according to your needs, write whatever you want here, be creative!
// this function will be used by all direct lights (directional/point/spot)
half3 ShadeSingleLightDefaultMethod(ToonSurfaceData surfaceData, LightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 N = lightingData.normalWS;
    half3 L = light.direction;
    half3 V = lightingData.viewDirectionWS;
    half3 H = normalize(L+V);
	half3 shadowColor = surfaceData._shadowColor;

    half NoL = dot(N,L);

    // ====== Module Start: Genshin style facial shading ======

	float lightAttenuation = CustomFaceShade(surfaceData, lightingData, light, isAdditionalLight);

	// ====== Module End ======


    // light's shadow map. If you prefer hard shadow, you can smoothstep() light.shadowAttenuation to make it sharp.
    lightAttenuation *= lerp(1,light.shadowAttenuation,_ReceiveShadowMappingAmount);

    // light's distance & angle fade for point light & spot light (see GetAdditionalPerObjectLight() in Lighting.hlsl)
    // Lighting.hlsl -> https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
    lightAttenuation *= min(1,light.distanceAttenuation); //max intensity = 1, prevent over bright if light too close, can expose this float to editor if you wish to

    // N dot L
    // simplest 1 line cel shade, you can always replace this line by your own better method !
    half celShadeResult = smoothstep(_CelShadeMidPoint-_CelShadeSoftness,_CelShadeMidPoint+_CelShadeSoftness, NoL);

    lightAttenuation *= lerp(celShadeResult,1, isAdditionalLight? _AdditionalLightIgnoreCelShade : _MainLightIgnoreCelShade);

    // don't want direct lighting becomes too bright for toon lit characters? set this value to a lower value 
    lightAttenuation *= _DirectLightMultiplier;

    // occlusion
    // extra separated control for indirect occlusion
    half directOcclusion = lerp(1, surfaceData.occlusion, _OcclusionDirectStrength);
    lightAttenuation *= directOcclusion;

	/*
	// Shadow color;
	half shadowDot = pow(dot(s.Normal, L) * 0.5 + 0.5, 0.75);
	float threshold = smoothstep(0.5, _ShadowSoftness, shadowDot);
	half3 diffuseTerm = saturate(threshold * atten);
	half3 diffuse = lerp(shadowColor, light.color.rgb, diffuseTerm);
	*/

	half3 result = surfaceData.albedo * min(1, light.color * lightAttenuation);

    return result; // use min(1,x) to prevent over bright for direct light
}

half3 CompositeAllLightResultsDefaultMethod(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, half3 faceShadowMask, ToonSurfaceData surfaceData, LightingData lightingData)
{

	half3 shadowColor = lerp(2*surfaceData._shadowColor, 1, faceShadowMask);
	half3 result = indirectResult*shadowColor + mainLightResult + additionalLightSumResult + emissionResult;
    return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Implement your own lighting equation here! 
////////////////////////////////////////////////////////////////////////////////////////////////////////////

half3 ShadeGIYourMethod(ToonSurfaceData surfaceData, LightingData lightingData)
{
    return 0; //write your own equation here ! (see ShadeGIDefaultMethod(...))
}
half3 ShadeMainLightYourMethod(ToonSurfaceData surfaceData, LightingData lightingData, Light light)
{
    return 0; //write your own equation here ! (see ShadeSingleLightDefaultMethod(...))
}
half3 ShadeAllAdditionalLightsYourMethod(ToonSurfaceData surfaceData, LightingData lightingData, Light light)
{
    return 0; //write your own equation here ! (see ShadeSingleLightDefaultMethod(...))
}
half3 CompositeAllLightResultsYourMethod(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult)
{
    return 0; //write your own equation here ! (see CompositeAllLightResultsDefaultMethod(...))
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Once you have implemented a equation in the above section, switch to using your own lighting equation in below section!
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// We split lighting into: 
//- indirect
//- main light 
//- additional light (point light/spot light)
// for a more isolated lighting control, just in case you need a separate equation for main light & additional light, you can do it easily here

half3 ShadeGI(ToonSurfaceData surfaceData, LightingData lightingData)
{
    //you can switch to ShadeGIYourMethod(...) !
    return ShadeGIDefaultMethod(surfaceData, lightingData); 
}
half3 ShadeMainLight(ToonSurfaceData surfaceData, LightingData lightingData, Light light)
{
    //you can switch to ShadeMainLightYourMethod(...) !
    return ShadeSingleLightDefaultMethod(surfaceData, lightingData, light, false); 

}
half3 ShadeFaceShadow(ToonSurfaceData surfaceData, LightingData lightingData, Light light)
{
	return CustomFaceShade(surfaceData, lightingData, light, false);
}
half3 ShadeAdditionalLight(ToonSurfaceData surfaceData, LightingData lightingData, Light light)
{
    //you can switch to ShadeAllAdditionalLightsYourMethod(...) !
    return ShadeSingleLightDefaultMethod(surfaceData, lightingData, light, true); 
}
half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, half3 faceShadowMask, ToonSurfaceData surfaceData, LightingData lightingData)
{
    //you can switch to CompositeAllLightResultsYourMethod(...) !
    return CompositeAllLightResultsDefaultMethod(indirectResult,mainLightResult,additionalLightSumResult,emissionResult, faceShadowMask, surfaceData, lightingData); 
}

#endif
