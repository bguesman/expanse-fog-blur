Shader "FullScreen/ExpanseFogBlur"
{
    Properties {
        _BlurAmount ("BlurAmount", Range(0.0, 1.0)) = 0.25
    }

    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Sky/SkyUtils.hlsl"
    #include "Assets/Expanse/code/source/atmosphere/AtmosphereGlobalTextures.hlsl"
    #include "Assets/Expanse/code/source/atmosphere/AtmosphereMapping.hlsl"
    #include "Assets/Expanse/code/source/atmosphere/AtmosphereGeometry.hlsl"
    #include "Assets/Expanse/code/source/common/Mapping.hlsl"
    #include "Assets/Expanse/code/source/clouds/CloudGlobalTextures.hlsl"
    #include "Assets/Expanse/code/source/directLight/planet/PlanetGlobals.hlsl"

    // Properties.
    float _BlurAmount;
    TEXTURE2D_X(_BlurBuffer);

    // Commented reference implementation that is inefficient. This is broken up into 2 1-D kernel implementations
    // below that are called by the C# custom pass.
    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        // Collect scene + fragment params.
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float3 view = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float3 d = -GetSkyViewDirWS(posInput.positionNDC * _ScreenParams.xy);
        float4 color = float4(0.0, 0.0, 0.0, 1.0);

        // Compute the linear depth of the pixel. It's one of:
        //  - the geometry depth
        //  - the cloud depth
        //  - the intersection with the planet/atmosphere
        float linear01Depth = Linear01Depth(depth, _ZBufferParams);
        if (linear01Depth >= 1) {
            float cloudHit;
            float3 cloudT, cloudColor;
            SampleExpanseClouds_float(posInput.positionNDC, cloudColor, cloudT, cloudHit);
            if (cloudHit < 0) {
                linear01Depth = saturate((cloudHit * _ProjectionParams.w * dot(view, d)));
            } else {
                PlanetRenderSettings planet = _ExpansePlanetRenderSettings[0];
                float3 o = Mapping::transformPointToPlanetSpace(_WorldSpaceCameraPos.xyz, planet.originOffset.xyz, planet.radius);
                SkyIntersectionData intersection = AtmosphereGeometry::traceSkyVolume(o, d, planet.radius, planet.atmosphereRadius);
                linear01Depth = saturate((intersection.endT * _ProjectionParams.w * dot(view, d)));
            }
        }

        // Refraction amount is likely proportional to how much light is attenuated by being out-scattered.
        // Because of this, we can make the blur radius proportional to the fog transmittance. Naturally
        // this is a huge hack, but to do this properly would require us essentially path tracing the
        // the entire scene. In practice, using the alpha to the fourth power gives a nice blur curve.
        // Also, make sure to normalize to screen resolution, so the blur looks the same at different resolutions.
        float4 fog;
        SampleExpanseFog_float(linear01Depth, posInput.positionNDC, fog);
        int blurRadius = clamp(pow(1-fog.w, 4) * _BlurAmount * 32, 0, 64) * (_ScreenParams.x / 1920);
        float totalWeight = 0;
        for (int i = -blurRadius; i < blurRadius + 1; i++) {
            for (int j = -blurRadius; j < blurRadius + 1; j++) {
                float2 samplePos = clamp(varyings.positionCS.xy - float2(i, j), 0, _ScreenParams.xy - 1);
                float sampleDepth = Linear01Depth(LoadCameraDepth(samplePos), _ZBufferParams);
                // Filter out samples that are closer than the center sample, so that we preserve
                // sharp edges.
                if (sampleDepth >= linear01Depth) {
                    float weight = saturate(1 - abs(i)/(blurRadius + 1));
                    color.xyz += weight * CustomPassLoadCameraColor(samplePos, 0);
                    totalWeight += weight;
                }
            }
        }
        color.xyz /= totalWeight;

        // Fade value allow you to increase the strength of the effect while the camera gets closer to the custom pass volume
        float f = 1 - abs(_FadeValue * 2 - 1);
        return float4(color.rgb + f, color.a);
    }

    float4 BlurHorizontal(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float3 view = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float3 d = -GetSkyViewDirWS(posInput.positionNDC * _ScreenParams.xy);
        float4 color = float4(0.0, 0.0, 0.0, 1.0);

        float linear01Depth = Linear01Depth(depth, _ZBufferParams);
        if (linear01Depth >= 1) {
            float cloudHit;
            float3 cloudT, cloudColor;
            SampleExpanseClouds_float(posInput.positionNDC, cloudColor, cloudT, cloudHit);
            if (cloudHit < 0) {
                linear01Depth = saturate((cloudHit * _ProjectionParams.w * dot(view, d)));
            } else {
                PlanetRenderSettings planet = _ExpansePlanetRenderSettings[0];
                float3 o = Mapping::transformPointToPlanetSpace(_WorldSpaceCameraPos.xyz, planet.originOffset.xyz, planet.radius);
                SkyIntersectionData intersection = AtmosphereGeometry::traceSkyVolume(o, d, planet.radius, planet.atmosphereRadius);
                linear01Depth = saturate((intersection.endT * _ProjectionParams.w * dot(view, d)));
            }
        }

        float4 fog;
        SampleExpanseFog_float(linear01Depth, posInput.positionNDC, fog);
        int blurRadius = clamp(pow(1-fog.w, 4) * _BlurAmount * 32, 0, 64) * (_ScreenParams.x / 1920);
        float totalWeight = 1;
        color.xyz += CustomPassLoadCameraColor(varyings.positionCS.xy, 0);
        for (int i = -blurRadius; i < blurRadius + 1; i+=2) {
            float2 samplePos = clamp(varyings.positionCS.xy - float2(i, 0), 0, _ScreenParams.xy - 1);
            float sampleDepth = Linear01Depth(LoadCameraDepth(samplePos), _ZBufferParams);
            if (sampleDepth >= linear01Depth) {
                float weight = saturate(1 - abs(i + 0.5)/(blurRadius + 1));
                color.xyz += weight * CustomPassSampleCameraColor((samplePos + 1) / _ScreenParams.xy, 0);
                totalWeight += weight;
            }
        }
        color.xyz /= totalWeight;

        float f = 1 - abs(_FadeValue * 2 - 1);
        return float4(color.rgb + f, color.a);
    }

    float4 BlurVertical(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float3 view = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float3 d = -GetSkyViewDirWS(posInput.positionNDC * _ScreenParams.xy);
        float4 color = float4(0.0, 0.0, 0.0, 1.0);

        float linear01Depth = Linear01Depth(depth, _ZBufferParams);
        if (linear01Depth >= 1) {
            float cloudHit;
            float3 cloudT, cloudColor;
            SampleExpanseClouds_float(posInput.positionNDC, cloudColor, cloudT, cloudHit);
            if (cloudHit < 0) {
                linear01Depth = saturate((cloudHit * _ProjectionParams.w * dot(view, d)));
            } else {
                PlanetRenderSettings planet = _ExpansePlanetRenderSettings[0];
                float3 o = Mapping::transformPointToPlanetSpace(_WorldSpaceCameraPos.xyz, planet.originOffset.xyz, planet.radius);
                SkyIntersectionData intersection = AtmosphereGeometry::traceSkyVolume(o, d, planet.radius, planet.atmosphereRadius);
                linear01Depth = saturate((intersection.endT * _ProjectionParams.w * dot(view, d)));
            }
        }

        float4 fog;
        SampleExpanseFog_float(linear01Depth, posInput.positionNDC, fog);
        int blurRadius = clamp(pow(1-fog.w, 4) * _BlurAmount * 32, 0, 64) * (_ScreenParams.x / 1920);
        float totalWeight = 1;
        color.xyz += SAMPLE_TEXTURE2D_X_LOD(_BlurBuffer, s_linear_clamp_sampler, (varyings.positionCS.xy + 0.5) / _ScreenParams, 0);
        // for (int i = -blurRadius; i < blurRadius + 1; i+=2) {
        //     float2 samplePos = clamp(varyings.positionCS.xy - float2(0, i), 0, _ScreenParams.xy - 1);
        //     float sampleDepth = Linear01Depth(LoadCameraDepth(samplePos), _ZBufferParams);
        //     if (sampleDepth >= linear01Depth) {
        //         float weight = saturate(1 - abs(i + 0.5)/(blurRadius + 1));
        //         color.xyz += weight * SAMPLE_TEXTURE2D_X_LOD(_BlurBuffer, s_linear_clamp_sampler, (samplePos + 1) / _ScreenParams, 0);
        //         totalWeight += weight;
        //     }
        // }
        int i = -blurRadius;
        while (i < blurRadius + 1) {
            int mip = floor(log2(abs(i / 2)));
            float sampleSize = max(1, pow(2, mip));
            float2 samplePos = clamp(varyings.positionCS.xy + float2(0, i + sampleSize * 0.5), 0, _ScreenParams.xy - 1);
            float sampleDepth = Linear01Depth(LoadCameraDepth(samplePos), _ZBufferParams);
            if (sampleDepth >= linear01Depth) {
                float weight = saturate(1 - abs(i + sampleSize * 0.5)/(blurRadius + 1));
                color.xyz += weight * SAMPLE_TEXTURE2D_X_LOD(_BlurBuffer, s_linear_clamp_sampler, samplePos / _ScreenParams, mip);
                totalWeight += weight;
            }
            i += sampleSize;
        }
        color.xyz /= totalWeight;

        float f = 1 - abs(_FadeValue * 2 - 1);
        return float4(color.rgb + f, color.a);
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Custom Pass 0"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma fragment FullScreenPass
            ENDHLSL
        }

        Pass
        {
            Name "Blur Horizontal"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma fragment BlurHorizontal
            ENDHLSL
        }

        Pass
        {
            Name "Blur Vertical"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma fragment BlurVertical
            ENDHLSL
        }
    }
    Fallback Off
}
