#include <metal_stdlib>
using namespace metal;
struct DisplaySettings { uint field,palette;float exposure,contrast;uint contours;float scale;uint padding0,padding1; };
struct VertexOut { float4 position [[position]];float2 uv; };
vertex VertexOut fullscreenVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2);return {float4(p*2-1,0,1),float2(p.x,1-p.y)};
}
float3 palette(float t,uint map) {
    t=clamp(t,0.f,1.f);
    if(map==0) {
        float3 cold=float3(0.10,0.64,1.0),hot=float3(1.0,0.23,0.065),zero=float3(0.018,0.025,0.047);
        float v=abs(2*t-1);return mix(zero,t<0.5?cold:hot,pow(v,0.7f))+float3(0.36)*pow(v,5.f);
    }
    if(map==1) {
        const float3 colors[6]={float3(0.001,0,0.014),float3(0.22,0.035,0.39),float3(0.58,0.15,0.40),float3(0.87,0.32,0.23),float3(0.98,0.65,0.04),float3(0.99,1,0.64)};
        float f=t*5;uint j=min(uint(f),4u);return mix(colors[j],colors[j+1],f-j);
    }
    if(map==2) {
        float4 v=float4(1,t,t*t,t*t*t);float2 v2=v.zw*v.z;
        return saturate(float3(dot(v,float4(0.13572138,4.61539260,-42.66032258,132.13108234))+dot(v2,float2(-152.94239396,59.28637943)),dot(v,float4(0.09140261,2.19418839,4.84296658,-14.18503333))+dot(v2,float2(4.27729857,2.82956604)),dot(v,float4(0.10667330,12.64194608,-60.58204836,110.36276771))+dot(v2,float2(-89.90310912,27.34824973))));
    }
    float3 a=float3(0.03,0.015,0.08),b=float3(0.0,0.9,0.72),c=float3(1.0,0.1,0.66);
    return t<0.5?mix(a,b,t*2):mix(b,c,(t-0.5)*2);
}
fragment float4 fieldFragment(VertexOut in [[stage_in]], texture2d<float> field [[texture(0)]], constant DisplaySettings &s [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized,address::repeat,filter::linear);
    float4 data=field.sample(linearSampler,in.uv);
    float value=data[s.field];bool signedField=s.field==0 || s.field==2;
    float z=value*exp2(s.exposure)/max(s.scale,1.e-8f);
    float t=signedField ? 0.5f+0.5f*tanh(z*s.contrast) : 1-exp(-max(z,0.f)*s.contrast);
    float3 rgb=palette(t,s.palette);
    if(s.contours) { float band=abs(fract(t*16)-0.5f);float aa=max(fwidth(t)*16,0.01f);rgb*=0.68f+0.32f*smoothstep(0.03f,0.03f+aa,band); }
    if(!isfinite(value)) rgb=float3(1,0,1);
    return float4(rgb,1);
}
