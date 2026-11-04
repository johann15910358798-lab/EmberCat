// Vertical rain disappears at the movable shadow, with a breathing core and cursor feedback.
enum NotchMatrixShader {
    static let source = #"""

    float matrixGlyph(texture2d<float> atlas, float2 local, float index) {
        if (any(local < 0.0) || any(local > 1.0)) return 0.0;
        constexpr sampler lookup(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 tile = float2(fmod(index,8.0),floor(index/8.0));
        return atlas.sample(lookup,(tile+(local*30.0+1.0)/32.0)/8.0).a;
    }

    fragment float4 matrixFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]],
        constant float4 *ports [[buffer(1)]], constant float4 &hole [[buffer(2)]],
        constant float4 *flashes [[buffer(3)]]) {
        if (u.visibility < .0001) return float4(0.0);
        float2 p = in.uv*u.viewport;
        float2 edge = rim(p,u);
        float aa = .65/u.pixelScale;
        float outside = smoothstep(-aa,aa,edge.y);
        float3 black = float3(.001,.003,.002);
        float anchor = (1.0-outside)*u.drawsAnchor;
        if (edge.y < -aa || u.heat < .0001) return float4(black*anchor,anchor)*u.visibility;

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
        float angle = atan2(relative.y,relative.x);
        float exposed = smoothstep(.25,2.0,below);
        float lightWeight = (.74+.26*cos(angle+.60))
            *(.96+.04*sin(u.time*.45+angle*2.0))*exposed;
        float glowWidth = clamp(radius*.12,.95,2.5)*u.matrixInteraction.w;
        float innerLight = exp(-pow((distance-radius+glowWidth*.58)/glowWidth,2.0))*core
            *(.28+.02*sqrt(saturate(u.heat)));
        float outerDistance = max(0.0,distance-radius);
        float outerLight = exp(-pow(outerDistance/glowWidth,2.0))*(1.0-core)*.10
            *(1.0-smoothstep(3.75*u.matrixInteraction.w,5.0*u.matrixInteraction.w,outerDistance));
        shadow = over(float3(.035,1.0,.29),(innerLight+outerLight)*lightWeight,shadow);
        // The integrated heart phase speeds up with smoothed tok/s without resets.
        float beat = u.matrixInteraction.y;
        float heartScale = u.matrixInteraction.z;
        float heartRadius = max(2.0,radius*(.14+.038*beat))*heartScale;
        float heart = exp(-pow(distance/heartRadius,2.0))*(.07+.23*beat);
        heart += exp(-pow(distance/(radius*.40*heartScale),2.0))*(.025+.060*beat);
        heart *= core*(1.0-smoothstep(radius*min(.52*heartScale,.72),radius*min(.72*heartScale,.90),distance));
        shadow = over(float3(.06,.95,.35),heart,shadow);
        // Each brief fluorescent spot starts inside a real glyph entry point.
        // Saturating the sum keeps simultaneous arrivals from becoming a bright ring.
        float captureLight = 0.0;
        for (uint i=0;i<uint(u.motion.w);++i) {
            float d = length(p-flashes[i].xy)/max(.5,flashes[i].w);
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
        // Only incoming glyphs illuminate the edge. Their broken, moving highlights
        // reveal the shadow without adding a separate outline or disk surface.
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
