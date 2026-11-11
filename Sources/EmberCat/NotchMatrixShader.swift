// Compact accretion disk and lensed arcs around the code sink.
// Geodesic integration adapted from s0xDk/ghostty-blackhole (MIT, s13k).
// See Vendor/GHOSTTY-BLACKHOLE-LICENSE. Desktop content is never sampled.
enum NotchMatrixShader {
    static let source = #"""

    float matrixDiskNoise(float2 p, float period) {
        float2 cell = floor(p), f = fract(p);
        f = f*f*(3.0-2.0*f);
        float y0 = cell.y-period*floor(cell.y/period);
        float y1 = cell.y+1.0-period*floor((cell.y+1.0)/period);
        float a = hash(cell.x*37.0+y0*113.0);
        float b = hash((cell.x+1.0)*37.0+y0*113.0);
        float c = hash(cell.x*37.0+y1*113.0);
        float d = hash((cell.x+1.0)*37.0+y1*113.0);
        return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
    }

    // Trace only the small region that can intersect the disk. The apparent
    // shadow radius remains shared with capture, pointer feedback and breathing.
    float4 matrixAccretionRay(float2 relative, float radius, constant Uniforms &u,
        texture2d<float> matter) {
        const float critical = 2.5980762;
        float width = u.matrixInteraction.w;
        float outer = mix(5.6,7.25,saturate((width-.4)/1.4));
        float2 q = float2(.995*relative.x+.100*relative.y,
                         -.100*relative.x+.995*relative.y)/max(radius,.5);
        float screenRadius = length(q);
        if (screenRadius > outer/critical+.12) return float4(0.0);
        float3 x = float3(q.x*critical,-q.y*critical,14.0);
        float3 v = float3(0.0,0.0,-1.0);
        float angularMomentum = dot(x.xy,x.xy);
        // The reference's 1.52-radian inclination makes a fine foreground blade.
        // Light from the far side still bends into a broad arch above the shadow.
        float3 normal = float3(0.0,.99871014,.05077449);
        float3 vertical = float3(0.0,.05077449,-.99871014);
        float previousSide = dot(x,normal);
        float energy = 0.0, transmission = 1.0;
        float inner = 2.2;
        for (uint step=0;step<72;++step) {
            float r2 = dot(x,x);
            if (r2 < 1.0 || x.z < -14.0 || r2 > 784.0) break;
            float r = sqrt(r2);
            float dt = clamp(.16*r,.03,1.5);
            float3 previous = x;
            float3 acceleration = -1.5*angularMomentum*x/(r2*r2*r);
            v += acceleration*(.5*dt);
            x += v*dt;
            r2 = max(dot(x,x),.0001);
            r = sqrt(r2);
            acceleration = -1.5*angularMomentum*x/(r2*r2*r);
            v += acceleration*(.5*dt);
            float side = dot(x,normal);
            if (side*previousSide < 0.0 && transmission > .025) {
                float3 crossing = mix(previous,x,previousSide/(previousSide-side));
                float orbitRadius = length(crossing);
                if (orbitRadius > inner && orbitRadius < outer) {
                    float band = smoothstep(inner,inner+.50,orbitRadius)
                        *(1.0-smoothstep(outer*.74,outer,orbitRadius));
                    float angle = atan2(dot(crossing,vertical),crossing.x);
                    float properRate = sqrt(max(.04,1.0-1.5/orbitRadius));
                    float orbit = u.time*1.8*pow(inner/orbitRadius,1.5)*properRate;
                    float turns = angle/(2.0*M_PI_F)+.5;
                    // Wrapped angular fields keep the atan seam invisible. Thin,
                    // uneven strands sit inside slower, broken density pockets.
                    float cloud = matrixDiskNoise(float2(orbitRadius*2.8,
                        turns*24.0+orbitRadius*2.1-orbit),24.0);
                    float warp = matrixDiskNoise(float2(orbitRadius*7.0,
                        turns*48.0-orbit*2.0),48.0);
                    float grain = matrixDiskNoise(float2(orbitRadius*34.0+warp*.85,
                        turns*96.0+orbitRadius*8.0-orbit*5.0),96.0);
                    float threads = pow(saturate(grain),3.5);
                    float streak = (.26+2.6*threads)*(.44+.85*cloud*cloud);
                    float3 gasDirection = normalize(cross(normal,crossing));
                    float velocity = rsqrt(max(2.0*(orbitRadius-1.0),.2));
                    float shift = properRate/max(.15,1.0+velocity*dot(gasDirection,normalize(v)));
                    float temperature = pow(inner/orbitRadius,.75)
                        *pow(max(0.0,1.0-sqrt(inner/orbitRadius)),.25)/.488;
                    constexpr sampler matterLookup(coord::normalized,address::repeat,filter::linear);
                    float4 captured = matter.sample(matterLookup,
                        float2(turns,(orbitRadius-inner)/(outer-inner)));
                    // The light is made by captured rain glyphs. Their shapes
                    // remain legible outside the shadow and melt in the front blade.
                    float readable = smoothstep(.98,1.13,screenRadius);
                    float codeEdge = smoothstep(inner,inner+.12,orbitRadius)
                        *(1.0-smoothstep(outer-.10,outer,orbitRadius));
                    float density = band*streak*.10
                        +codeEdge*(captured.r*.32*readable+captured.g*mix(1.8,.65,readable));
                    energy += transmission*density*temperature*temperature
                        *pow(mix(1.0,shift,.55),2.6)*3.2;
                    transmission *= 1.0-saturate(density*.72);
                }
            }
            previousSide = side;
        }
        // All emission comes from a disk crossing. There is no center lamp or
        // artificial radial cutout interrupting the thin foreground blade.
        energy *= 1.0-smoothstep(outer/critical-.06,outer/critical+.12,screenRadius);
        float alpha = 1.0-exp(-energy*1.65);
        float hot = 1.0-exp(-energy*.85);
        float3 luminous = mix(float3(.025,.60,.20),float3(.28,1.0,.55),hot);
        luminous = mix(luminous,float3(.78,1.0,.87),smoothstep(.85,2.4,energy));
        // The disk shares the Matrix KV: green filaments, a cool-white hot
        // edge, and dark teal ink under the system's light appearance.
        float3 ink = mix(float3(.008,.13,.085),float3(.02,.34,.20),hot);
        float3 color = mix(luminous,ink,u.motion.z);
        return float4(color*alpha,alpha);
    }

    float4 matrixAccretion(float2 relative, float radius, constant Uniforms &u,
        texture2d<float> matter) {
        if (length(relative) > radius*2.92+1.0) return float4(0.0);
        // Integrate the subpixel blade and filaments instead of letting one ray
        // alternately miss and hit them at native menu-bar sizes.
        float pixel = .25/u.pixelScale;
        return (matrixAccretionRay(relative+float2(-pixel,-pixel),radius,u,matter)
            +matrixAccretionRay(relative+float2(pixel,-pixel),radius,u,matter)
            +matrixAccretionRay(relative+float2(-pixel,pixel),radius,u,matter)
            +matrixAccretionRay(relative+float2(pixel,pixel),radius,u,matter))*.25;
    }

    float matrixGlyph(texture2d<float> atlas, float2 local, float index) {
        if (any(local < 0.0) || any(local > 1.0)) return 0.0;
        constexpr sampler lookup(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 tile = float2(fmod(index,8.0),floor(index/8.0));
        return atlas.sample(lookup,(tile+(local*30.0+1.0)/32.0)/8.0).a;
    }

    fragment float4 matrixFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]],
        constant float4 *ports [[buffer(1)]], constant float4 &hole [[buffer(2)]],
        constant float4 *flashes [[buffer(3)]],texture2d<float> matter [[texture(2)]]) {
        if (u.visibility < .0001) return float4(0.0);
        float2 p = in.uv*u.viewport;
        float2 edge = rim(p,u);
        float aa = .65/u.pixelScale;
        float outside = smoothstep(-aa,aa,edge.y);
        float3 black = float3(.001,.003,.002);
        float anchor = (1.0-outside)*u.drawsAnchor;
        if (edge.y < -aa) return float4(black*anchor,anchor)*u.visibility;

        float4 result = float4(0.0);
        float n = max(edge.y,0.0);
        float3 green = float3(.055,.95,.39);
        float3 mint = float3(.70,1.0,.82);
        float2 relative = p-hole.xy;
        float radius = hole.z;
        float distance = length(relative);
        float portLight = 0.0;
        for (uint i=0; i<uint(u.motion.y); ++i) {
            float offset = (p.x-ports[i].x)/max(ports[i].z,1.0);
            portLight += exp(-offset*offset)*ports[i].y;
        }
        float below = p.y-u.notchSize.y;
        portLight = saturate(portLight)*(1.0-smoothstep(2.0,6.0,abs(below)));
        // End the notch rim at the actual mouth. A broad dimmed gap merges the
        // shadow with the notch and erases the two sides of the opening.
        float aperture = (1.0-smoothstep(radius+.20,radius+2.8,distance))
            *(1.0-smoothstep(0.0,5.0,abs(below)));
        float rimWeight = 1.0-aperture*.98;
        float rimLight = pow(.5+.5*sin(edge.x*.052-u.time*1.65),7.0);
        float halo = exp(-n/1.55)*(.13+.28*portLight)*(1.0-smoothstep(3.0,4.5,n));
        result = over(green,halo*rimWeight,result);
        result = over(float3(.003,.021,.010),(1.0-smoothstep(2.0,3.0,n))*.85*rimWeight,result);
        float stroke = 1.0-smoothstep(1.15-aa,1.15+aa,n);
        result = over(mix(green,mint,saturate(.08+.78*rimLight+.50*portLight)),stroke*.70*rimWeight,result);

        // Cursor feedback belongs to this local layer, leaving the notch and
        // distant rain intact. Feathering softens the edge as the hole fades.
        float hover = u.matrixInteraction.x;
        float feather = mix(aa,3.4,hover);
        float core = 1.0-smoothstep(radius-feather,radius+feather,distance);
        float4 shadow = over(black,core,float4(0.0));
        float4 disk = matrixAccretion(relative,radius,u,matter);
        float footprint = smoothstep(.5,3.0,min(p.x-u.notchOrigin.x,
            u.notchOrigin.x+u.notchSize.x-p.x));
        disk *= footprint;
        shadow = disk+shadow*(1.0-disk.a);
        float angle = atan2(relative.y,relative.x);
        float ringWidth = max(.26/u.pixelScale,radius*.009);
        float photon = exp(-pow((distance-radius-.12)/ringWidth,2.0))
            *(.06+.12*(.5+.5*cos(angle+1.0)));
        float3 photonColor = mix(float3(.56,1.0,.78),float3(.01,.28,.18),u.motion.z);
        shadow = over(photonColor,photon,shadow);
        // The center stays unlit. Breathing changes the shared physical radius.
        // Each brief fluorescent spot starts inside a real glyph entry point.
        // Saturating the sum keeps simultaneous arrivals from becoming a bright ring.
        float captureLight = 0.0;
        for (uint i=0;i<uint(u.motion.w);++i) {
            float2 radial = normalize(flashes[i].xy-hole.xy+float2(.0001));
            float2 tangent = float2(-radial.y,radial.x);
            float2 delta = p-flashes[i].xy;
            float2 local = float2(dot(delta,radial)/.65,dot(delta,tangent)/2.1);
            float d = length(local)/max(.5,flashes[i].w);
            captureLight += exp(-d*d*1.5)*flashes[i].z;
        }
        captureLight = min(.26,captureLight)*core*(1.0-smoothstep(radius-.25,radius,distance));
        shadow = over(float3(.16,1.0,.48),captureLight,shadow);
        shadow *= mix(1.0,.12,hover);
        result = shadow+result*(1.0-shadow.a);
        result.rgb = result.rgb*outside+black*(1.0-outside)*u.drawsAnchor;
        result.a = result.a*outside+(1.0-outside)*u.drawsAnchor;
        return result*u.visibility;
    }

    struct MatrixPulseVertexData { float4 positionAndUV; float4 material; };
    struct MatrixPulseVarying {
        float4 position [[position]];
        float2 point;
        float2 uv;
        float4 material;
    };

    vertex MatrixPulseVarying matrixMatterVertex(uint id [[vertex_id]],
        constant MatrixPulseVertexData *vertices [[buffer(1)]]) {
        MatrixPulseVertexData data = vertices[id];
        float2 p = data.positionAndUV.xy;
        return {float4(p.x*2.0-1.0,1.0-p.y*2.0,0,1),p,data.positionAndUV.zw,data.material};
    }

    fragment float4 matrixMatterFragment(MatrixPulseVarying in [[stage_in]],
        texture2d<float> atlas [[texture(1)]]) {
        float melt = smoothstep(.55,1.0,in.material.y);
        float row = floor(in.uv.y*7.0);
        float offset = (hash(in.material.w+row*13.7)-.5)*melt*.45;
        float2 uv = in.uv+float2(offset,0.0);
        float index = floor(hash(in.material.w)*64.0);
        float rawCode = matrixGlyph(atlas,uv,index);
        float fragmentLife = 1.0-smoothstep(.18+hash(in.material.w+row*3.2)*.62,1.0,melt);
        float code = rawCode*fragmentLife;
        float bloom = rawCode*.35;
        bloom += matrixGlyph(atlas,uv+float2(.12,0),index)*.16;
        bloom += matrixGlyph(atlas,uv-float2(.12,0),index)*.16;
        bloom += matrixGlyph(atlas,uv+float2(0,.12),index)*.16;
        bloom += matrixGlyph(atlas,uv-float2(0,.12),index)*.16;
        float energy = in.material.x;
        return float4(code*energy,bloom*(.18+.82*melt)*energy,0.0,energy*code);
    }

    fragment float4 matrixOrbitGlyphFragment(MatrixPulseVarying in [[stage_in]],
        constant Uniforms &u [[buffer(0)]],constant float4 &hole [[buffer(2)]],
        texture2d<float> atlas [[texture(1)]]) {
        float distance = length(in.point-hole.xy);
        float insideWidth = min(in.point.x-u.notchOrigin.x,u.notchOrigin.x+u.notchSize.x-in.point.x);
        float mask = smoothstep(.0,.8,insideWidth)*smoothstep(.0,.8,rim(in.point,u).y)
            *smoothstep(hole.z+.20,hole.z+.90,distance)
            *(1.0-smoothstep(u.viewport.y-5.0,u.viewport.y-1.0,in.point.y));
        float melt = smoothstep(.80,1.0,in.material.y);
        float row = floor(in.uv.y*7.0);
        float drift = (hash(in.material.w+row*13.7)-.5)*melt*.45;
        float2 uv = in.uv+float2(drift,0.0);
        float index = floor(hash(in.material.w)*64.0);
        float code = matrixGlyph(atlas,uv,index)
            *(1.0-smoothstep(.18+hash(in.material.w+row*3.2)*.62,1.0,melt));
        float bloom = matrixGlyph(atlas,uv+float2(.10,0),index)
            +matrixGlyph(atlas,uv-float2(.10,0),index)
            +matrixGlyph(atlas,uv+float2(0,.10),index)
            +matrixGlyph(atlas,uv-float2(0,.10),index);
        float alpha = in.material.x*in.material.z*mask*u.visibility*mix(1.0,.12,u.matrixInteraction.x);
        float3 green = mix(float3(.035,.95,.34),float3(.005,.24,.16),u.motion.z);
        float3 hot = mix(float3(.65,1.0,.80),float3(.005,.14,.10),u.motion.z);
        float glow = bloom*alpha*.07*mix(1.0,.15,u.motion.z);
        float4 result = float4(green*glow,glow);
        return over(mix(green,hot,.15+.5*melt),code*alpha,result);
    }

    vertex MatrixPulseVarying matrixPulseVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(0)]],
        constant MatrixPulseVertexData *vertices [[buffer(1)]]) {
        MatrixPulseVertexData data = vertices[id];
        float2 p = data.positionAndUV.xy;
        return {float4(p.x/u.viewport.x*2.0-1.0,1.0-p.y/u.viewport.y*2.0,0,1),
            p,data.positionAndUV.zw,data.material};
    }

    fragment float4 matrixPulseFragment(MatrixPulseVarying in [[stage_in]], constant Uniforms &u [[buffer(0)]],
        constant float4 &hole [[buffer(2)]],
        texture2d<float> atlas [[texture(1)]]) {
        float x = in.point.x-u.notchOrigin.x;
        float y = in.point.y-u.notchSize.y;
        float2 relative = in.point-hole.xy;
        float shadowDistance = length(relative);
        bool background = in.material.z < 0.0;
        // Light desktops need ink. Capture masks stay independent of appearance.
        float lightBackdrop = u.motion.z*smoothstep(hole.z-.5,hole.z+1.5,shadowDistance);
        // Absorption happens at the real silhouette. No foreground exception
        // paints glyphs back onto the dark surface or reveals them while hovering.
        float outsideNotch = smoothstep(0.0,.8,rim(in.point,u).y);
        float occlusion = background ? smoothstep(hole.z+.25,hole.z+1.25,shadowDistance)
            : smoothstep(hole.z-.35,hole.z+.65,shadowDistance);
        float mask = smoothstep(0.0,.8,min(x,u.notchSize.x-x))*outsideNotch
            *(1.0-smoothstep(102.0,111.0,y))*occlusion;
        float envelope = smoothstep(0.0,.16,in.material.y)*(.40+.60*sqrt(saturate(in.material.y)));
        float alpha = in.material.x*envelope*mask*u.visibility;
        // Incoming glyphs brighten before capture; the disk is composited over them.
        float edgeLight = (1.0-smoothstep(hole.z+1.2,hole.z+9.0,shadowDistance))
            *smoothstep(hole.z*.91,hole.z+.60,shadowDistance);
        edgeLight *= .72+.28*smoothstep(-hole.z,hole.z,relative.x);
        if (background) edgeLight = 0.0;
        alpha = saturate(alpha*(1.0+1.35*edgeLight)
            *mix(1.0,background ? 2.4 : 1.35,lightBackdrop));
        float hover = u.matrixInteraction.x*(1.0-smoothstep(hole.z+3.0,hole.z+13.0,shadowDistance));
        alpha *= mix(1.0,.20,hover);
        if (alpha < .001) return float4(0.0);
        float drift = (hash(in.material.w*9.7)-.5)*.08;
        float2 local = float2((in.uv.y+1.0)*.5+drift,in.uv.x);
        float codeIndex = floor(hash(in.material.w)*64.0);
        float code = matrixGlyph(atlas,local,codeIndex);
        // Every bit of visible light follows a character. There is no ribbon surface or rail.
        float bloom = code*.28;
        bloom += matrixGlyph(atlas,local+float2(.08,0),codeIndex)*.18;
        bloom += matrixGlyph(atlas,local-float2(.08,0),codeIndex)*.18;
        bloom += matrixGlyph(atlas,local+float2(0,.08),codeIndex)*.18;
        bloom += matrixGlyph(atlas,local-float2(0,.08),codeIndex)*.18;
        float scanning = .90+.10*sin(in.material.w*.16-u.time*1.3*abs(in.material.z));
        float head = pow(saturate(in.material.y),8.0);
        float variation = .78+.22*hash(in.material.w*7.3);
        float3 green = background ? float3(.06,.67,.31) : float3(.035,.98,.38);
        float3 mint = float3(.76,1.0,.86);
        float3 ink = background ? float3(.07,.31,.26) : float3(.015,.27,.21);
        green = mix(green,ink,lightBackdrop);
        mint = mix(mint,float3(.005,.14,.11),lightBackdrop);
        float glow = bloom*alpha*(.30+.12*edgeLight)*mix(1.0,.12,lightBackdrop);
        float4 result = float4(green*glow,glow);
        result = over(mix(green,mint,min(.85,head*.82+edgeLight*.44)),
            code*alpha*variation*scanning,result);
        return result;
    }
    """#
}
