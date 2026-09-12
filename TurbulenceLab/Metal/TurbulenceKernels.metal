#include <metal_stdlib>
using namespace metal;
constant float tau = 6.283185307179586f;
struct Params {
    uint n, count, stage, preset;
    float dt, viscosity, drag, cfl;
    uint automatic, seed, packed, realFFT;
    float force, injectionX, injectionY, injectionStrength;
};
struct Clock { float time, dt; uint steps, fault; float compensation; };
struct Diagnostic { float energy, enstrophy, maxOmega, maxSpeed; float time, dt; uint steps, fault; };
inline float2 cmul(float2 a, float2 b) { return float2(a.x*b.x-a.y*b.y,a.x*b.y+a.y*b.x); }
inline uint hash32(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16); }
inline float random01(uint x) { return float(hash32(x) >> 8) * (1.f/16777216.f); }
inline float periodic(float x) { return x - round(x/tau)*tau; }

kernel void coefficients(device float4 *coef [[buffer(0)]], device float2 *forcing [[buffer(1)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if (i >= p.count) return;
    int x = i%p.n, y=i/p.n;
    int kx=x<=int(p.n/2)?x:x-int(p.n), ky=y<=int(p.n/2)?y:y-int(p.n);
    float k2 = float(kx*kx+ky*ky);
    // Keep the full spectral band except the even-grid Nyquist lines and mean.
    bool keep = abs(kx) < int(p.n/2) && abs(ky) < int(p.n/2) && k2>0;
    coef[i] = float4(kx,ky,k2>0?1.f/k2:0.f,keep?1.f:0.f);
    uint mirror = ((p.n-y)%p.n)*p.n+(p.n-x)%p.n;
    uint key = min(i,mirror) ^ p.seed;
    float phase = tau*random01(key);
    forcing[i] = (k2>=64 && k2<=144 && keep) ? float(p.count)*0.035f*float2(cos(phase), (i<=mirror?1.f:-1.f)*sin(phase)) : float2(0);
}
kernel void initializeField(device float2 *w [[buffer(0)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=p.count) return;
    float x=tau*float(i%p.n)/p.n, y=tau*float(i/p.n)/p.n;
    float value=0;
    if (p.preset == 0 || p.preset == 3) {
        // A real, deterministic random phase spectrum, concentrated around |k|≈9.
        for(int j=0;j<48;j++) {
            uint h=hash32(p.seed+uint(j)*719u);
            int kx=int(h%19)-9, ky=int((h>>8)%19)-9;
            float k2=float(kx*kx+ky*ky);
            float amplitude=exp(-pow((sqrt(k2)-8.f)/3.f,2.f));
            value += 0.6f*amplitude*cos(kx*x+ky*y+tau*random01(h));
        }
    } else if(p.preset == 1) {
        for(uint j=0;j<40;j++) {
            float cx=tau*random01(p.seed+j*4), cy=tau*random01(p.seed+j*4+1);
            float dx=periodic(x-cx),dy=periodic(y-cy);
            value += (j%2? -10.f:10.f)*exp(-(dx*dx+dy*dy)/0.035f);
        }
    } else {
        // Smooth periodic double shear u(y)=tanh(sin(y)/δ), with a perturbation.
        float s=sin(y)/0.16f;
        value = -cos(y)/0.16f/(cosh(s)*cosh(s)) + 0.15f*cos(6*x)*exp(-pow(sin(y)/0.3f,2.f));
    }
    w[i]=float2(value,0);
}
kernel void filterState(device float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i<p.count && c[i].w==0) w[i] = 0;
}
// Gather signed N-grid modes into the M=3N/2 FFT grid, clearing every other
// entry on every stage. Scale by M²/N² for VkFFT's normalized inverse.
inline int unpaddedIndex(uint i, uint n) {
    int m=int(n*3/2),x=int(i)%m,y=int(i)/m;
    int kx=x<=m/2?x:x-m,ky=y<=m/2?y:y-m;
    if(abs(kx)>=int(n/2) || abs(ky)>=int(n/2)) return -1;
    return (ky<0?ky+int(n):ky)*int(n)+(kx<0?kx+int(n):kx);
}
kernel void derivePacked(device const float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], device float2 *velocity [[buffer(2)]], device float2 *gradient [[buffer(3)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    uint m=p.n*3/2;if(i>=m*m) return;
    int j=unpaddedIndex(i,p.n);
    velocity[i]=0;gradient[i]=0;
    if(j<0 || c[j].w==0) return;
    float4 k=c[j]; float2 z=w[j]*(float(m*m)/float(p.count));
    velocity[i]=cmul(float2(k.x,k.y)*k.z,z); // u_hat + i v_hat
    gradient[i]=cmul(float2(-k.y,k.x),z);    // wx_hat + i wy_hat
}
kernel void deriveSeparate(device const float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], device float2 *u [[buffer(2)]], device float2 *v [[buffer(3)]], device float2 *dx [[buffer(4)]], device float2 *dy [[buffer(5)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    uint m=p.n*3/2;if(i>=m*m) return;
    int j=unpaddedIndex(i,p.n);
    u[i]=0;v[i]=0;dx[i]=0;dy[i]=0;
    if(j<0 || c[j].w==0) return;
    float4 k=c[j];float2 iz=float2(-w[j].y,w[j].x)*(float(m*m)/float(p.count));
    u[i]=iz*k.y*k.z;v[i]=-iz*k.x*k.z;dx[i]=iz*k.x;dy[i]=iz*k.y;
}
kernel void nonlinear(device const float2 *u [[buffer(0)]], device const float2 *g [[buffer(1)]], device float2 *rhs [[buffer(2)]], device float *maxima [[buffer(3)]], device const float2 *dx [[buffer(4)]], device const float2 *dy [[buffer(5)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]], uint lid [[thread_index_in_threadgroup]], uint group [[threadgroup_position_in_grid]], uint width [[threads_per_threadgroup]]) {
    threadgroup float speeds[512];
    uint m=p.n*3/2;
    float2 vel=0,grad=0;
    if(i<m*m) {
        vel=p.packed?u[i]:float2(u[i].x,g[i].x); grad=p.packed?g[i]:float2(dx[i].x,dy[i].x);
        if(p.realFFT) {
            device float *real=reinterpret_cast<device float *>(rhs);
            uint row=(i/m)*(m+2),x=i%m;
            real[row+x]=-dot(vel,grad);
            if(x==0) { real[row+m]=0;real[row+m+1]=0; }
        } else { rhs[i]=float2(-dot(vel,grad),0); }
    }
    speeds[lid]=all(isfinite(vel)) && all(isfinite(grad)) ? abs(vel.x)+abs(vel.y) : INFINITY;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for(uint s=width/2;s>0;s/=2) { if(lid<s) speeds[lid]=max(speeds[lid],speeds[lid+s]);threadgroup_barrier(mem_flags::mem_threadgroup); }
    if(lid==0 && p.stage==0) maxima[group]=speeds[0];
}
kernel void chooseDT(device const float *maxima [[buffer(0)]], device Clock *clock [[buffer(1)]], constant Params &p [[buffer(8)]], constant uint &groups [[buffer(9)]], uint lid [[thread_index_in_threadgroup]], uint width [[threads_per_threadgroup]]) {
    threadgroup float values[512]; float v=0;
    for(uint j=lid;j<groups;j+=width) v=max(v,maxima[j]);
    values[lid]=v;threadgroup_barrier(mem_flags::mem_threadgroup);
    for(uint s=width/2;s>0;s/=2) { if(lid<s) values[lid]=max(values[lid],values[lid+s]); threadgroup_barrier(mem_flags::mem_threadgroup); }
    if(lid==0) {
        float kmax=float(p.n/2-1);
        float limit=1.5f/max(p.viscosity*2*kmax*kmax+p.drag,1.e-10f);
        float adv=p.cfl*(tau/float(p.n*3/2))/max(values[0],1.e-6f);
        clock->dt=min(p.dt,limit);
        if(p.automatic) clock->dt=min(clock->dt,adv);
        if(!isfinite(values[0]) || !isfinite(clock->time)) { clock->fault=1;clock->dt=0; }
    }
}
kernel void rkUpdate(device float2 *w [[buffer(0)]], device float2 *base [[buffer(1)]], device const float2 *rhs [[buffer(2)]], device const float4 *c [[buffer(3)]], device const float2 *forcing [[buffer(4)]], device const Clock *clock [[buffer(5)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=p.count) return;
    if(c[i].w==0) { w[i]=0;if(p.stage==0) base[i]=0;return; }
    float2 z=w[i]; if(p.stage==0) base[i]=z;
    float k2=dot(c[i].xy,c[i].xy),dt=clock->dt;
    float t=clock->time+(p.stage==1?dt:(p.stage==2?dt*0.5f:0));
    // Smooth, seeded, band-limited forcing. Conjugate modes share frequency.
    float2 f=0;
    if(p.preset==3 && k2>=64 && k2<=144) {
        f=p.force*cos(t*(0.7f+0.01f*k2))*forcing[i];
    }
    float2 nonlinear;
    uint m=p.n*3/2,x=i%p.n,y=i/p.n;
    uint px=x<=p.n/2?x:x+m-p.n,py=y<=p.n/2?y:y+m-p.n;
    if(p.realFFT) {
        bool conjugate=px>m/2;
        uint j=conjugate?((m-py)%m)*(m/2+1)+(m-px):py*(m/2+1)+px;
        nonlinear=rhs[j]; if(conjugate) nonlinear.y=-nonlinear.y;
    } else { nonlinear=rhs[py*m+px]; }
    // Crop the padded transform back to N-grid DFT normalization.
    nonlinear *= float(p.count)/float(m*m);
    float2 next=z+dt*(nonlinear-(p.viscosity*k2+p.drag)*z+f);
    float a=p.stage==0?0.f:(p.stage==1?0.75f:1.f/3.f);
    w[i]=(a*base[i]+(1.f-a)*next)*c[i].w;
}
kernel void advanceClock(device Clock *clock [[buffer(0)]], uint i [[thread_position_in_grid]]) {
    if(i==0) {
        float increment=clock->dt-clock->compensation;
        float next=clock->time+increment;
        clock->compensation=(next-clock->time)-increment;
        clock->time=next;clock->steps++;
    }
}
kernel void prepareDisplay(device const float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], device float2 *a [[buffer(2)]], device float2 *b [[buffer(3)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=p.count)return;
    a[i]=cmul(float2(1,c[i].z),w[i]); // omega + i psi
    b[i]=cmul(float2(c[i].x,c[i].y)*c[i].z,w[i]);
}
kernel void diagnosticField(device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]], device float4 *partial [[buffer(2)]], texture2d<float,access::write> field [[texture(0)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]], uint lid [[thread_index_in_threadgroup]], uint group [[threadgroup_position_in_grid]], uint width [[threads_per_threadgroup]]) {
    threadgroup float4 data[512];float4 val=0;
    if(i<p.count) { float w=a[i].x,psi=a[i].y,speed=length(b[i]); float energy=0.5f*dot(b[i],b[i]),ens=0.5f*w*w;
        field.write(float4(w,speed,psi,ens),uint2(i%p.n,i/p.n)); val=float4(energy,ens,abs(w),speed);
        if(!all(isfinite(val))) val=float4(INFINITY);
    }
    data[lid]=val;threadgroup_barrier(mem_flags::mem_threadgroup);
    for(uint s=width/2;s>0;s/=2) { if(lid<s) { data[lid].xy+=data[lid+s].xy;data[lid].zw=max(data[lid].zw,data[lid+s].zw); } threadgroup_barrier(mem_flags::mem_threadgroup); }
    if(lid==0) partial[group]=data[0];
}
kernel void finishDiagnostic(device const float4 *partial [[buffer(0)]], device Diagnostic *out [[buffer(1)]], device const Clock *clock [[buffer(2)]], constant Params &p [[buffer(8)]], constant uint &groups [[buffer(9)]], uint lid [[thread_index_in_threadgroup]], uint width [[threads_per_threadgroup]]) {
    threadgroup float4 data[512];float4 val=0;
    for(uint j=lid;j<groups;j+=width) { val.xy+=partial[j].xy; val.zw=max(val.zw,partial[j].zw); }
    data[lid]=val;threadgroup_barrier(mem_flags::mem_threadgroup);
    for(uint s=width/2;s>0;s/=2) { if(lid<s) { data[lid].xy+=data[lid+s].xy;data[lid].zw=max(data[lid].zw,data[lid+s].zw); } threadgroup_barrier(mem_flags::mem_threadgroup); }
    if(lid==0) { out->energy=data[0].x/p.count;out->enstrophy=data[0].y/p.count;out->maxOmega=data[0].z;out->maxSpeed=data[0].w;out->time=clock->time;out->dt=clock->dt;out->steps=clock->steps;out->fault=clock->fault || !all(isfinite(data[0])); }
}
kernel void injectVortex(device float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=p.count)return;
    float2 k=c[i].xy;float phase=-tau*dot(k,float2(p.injectionX,p.injectionY));
    float radius=0.065f;
    float amp=p.injectionStrength*float(p.count)*radius*radius/(4.f*3.14159265f)*exp(-dot(k,k)*radius*radius/4.f);
    w[i]=(w[i]+amp*float2(cos(phase),sin(phase)))*c[i].w;
}
// Analytic operators used by the GPU correctness suite.
kernel void testOperator(device const float2 *w [[buffer(0)]], device const float4 *c [[buffer(1)]], device float2 *out [[buffer(2)]], constant Params &p [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=p.count)return;float2 z=w[i],iz=float2(-z.y,z.x);float4 k=c[i];
    switch(p.stage) {
        case 0: out[i]=iz*k.x;break;
        case 1: out[i]=-dot(k.xy,k.xy)*z;break;
        case 2: out[i]=k.z*z;break;
        case 3: out[i]=iz*k.y*k.z;break;
        case 4: out[i]=-iz*k.x*k.z;break;
        case 5: out[i]=cmul(float2(0,k.x),iz*k.y*k.z)+cmul(float2(0,k.y),-iz*k.x*k.z);break;
        default: out[i]=z*k.w;break;
    }
}
