using UnityEngine;
using UnityEngine.Rendering.HighDefinition;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

class ExpanseFogBlurCustomPass : CustomPass
{
    [Range(0, 1)]
    public float blurAmount = 0.25f;
    [Range(0, 1)]
    public float optimizationAmount = 1;

    // Temp buffer.
    RTHandle blurBuffer;
    Material blurMaterial;

    // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
    // When empty this render pass will render to the active camera render target.
    // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
    // The render pipeline will ensure target setup and clearing happens in an performance manner.
    protected override void Setup(ScriptableRenderContext renderContext, CommandBuffer cmd)
    {
        blurBuffer = RTHandles.Alloc(Vector2.one, TextureXR.slices, dimension: TextureXR.dimension,
            colorFormat: GraphicsFormat.B10G11R11_UFloatPack32, // We don't need alpha in the blur
            useDynamicScale: true, name: "ExpanseFogBlurBuffer");
        blurMaterial = CoreUtils.CreateEngineMaterial(Shader.Find("FullScreen/ExpanseFogBlur"));
    }

    protected override void Execute(CustomPassContext ctx)
    {
        if (blurMaterial == null) {
            return;
        }
        var blurProperties = new MaterialPropertyBlock();
        blurProperties.SetFloat("_BlurAmount", blurAmount);
        blurProperties.SetFloat("_OptimizationAmount", optimizationAmount);
        CoreUtils.DrawFullScreen(ctx.cmd, blurMaterial, blurBuffer, blurProperties, shaderPassId: 1);
        CoreUtils.SetRenderTarget(ctx.cmd, ctx.cameraColorBuffer, ctx.cameraDepthBuffer);
        blurProperties.SetTexture("_BlurBuffer", blurBuffer);
        CoreUtils.DrawFullScreen(ctx.cmd, blurMaterial, blurProperties, shaderPassId: 2);
    }

    protected override void Cleanup()
    {
        // Cleanup code
        RTHandles.Release(blurBuffer);
    }
}