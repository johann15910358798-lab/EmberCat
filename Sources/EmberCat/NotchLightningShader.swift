// Cartoon power meter matched to the user's three hamster GIFs. The generators,
// outlined meter and rooted electrical discharges share one suspended pose.
enum NotchLightningShader {
    static let source = #"""
    struct LightningUniforms {
        float4 shape; // thickness, notch distance, arc intensity, hamster gap
        float4 pose;  // horizontal/vertical displacement, roll angle, reserved
        float4 hamsterLeft;  // three fractional frame indices, display size
        float4 hamsterRight; // offset frame indices
        float4 hamsterAtlas; // columns, rows, wheel anchor x/y
    };

    struct LightningDischarge {
        float4 timing; // age, lifetime, power, random variation
        float4 shape;  // horizontal root, length, mirror, slant
    };

    float tubeDischargeEnvelope(float4 timing) {
        return timing.z*smoothstep(0.0,.018,timing.x)
            *(1.0-smoothstep(timing.y*.24,timing.y,timing.x));
    }

    float3 tubeWarm(float3 color,float amount) {
        // Preserve the violet body and white highlights, with a little crimson
        // entering the brightest currents only at the top of the energy range.
        return mix(color,float3(max(color.r,color.b),color.g*.88,color.b*.60),amount);
    }

    float2 tubeRotate(float2 p,float2 rotation) {
        return float2(p.x*rotation.x-p.y*rotation.y,p.x*rotation.y+p.y*rotation.x);
    }

    float tubeStage(float heat) {
        return clamp(heat < .574349
            ? (heat-.172427)/(.574349-.172427)
            : 1.0+(heat-.574349)/(1.0-.574349),0.0,2.0);
    }

    float4 tubeCell(texture2d<float> atlas,float2 uv,float column,float row) {
        if (any(uv < float2(0.0)) || any(uv > float2(1.0))) return float4(0.0);
        constexpr sampler linearSampler(coord::normalized,address::clamp_to_edge,filter::linear);
        uv = clamp(uv,float2(.5/512.0,.5/256.0),float2(1.0-.5/512.0,1.0-.5/256.0));
        return atlas.sample(linearSampler,float2((uv.x+column)/2.0,(uv.y+row)/6.0));
    }

    float4 tubeMaterial(texture2d<float> atlas,float2 uv,float column,float stage,float theme) {
        float first = floor(stage),second = min(2.0,first+1.0);
        return mix(tubeCell(atlas,uv,column,first+theme*3.0),
                   tubeCell(atlas,uv,column,second+theme*3.0),fract(stage));
    }

    float2 tubeLeakRoot(float stage,int group) {
        float2 a,b,c;
        if (group == 0) {
            a = float2(.28125,.486486);
            b = float2(.291451,.479592);
            c = float2(.269097,.478261);
        } else {
            a = float2(.792422,.260204);
            b = a;
            c = float2(.712674,.260870);
        }
        return stage < 1.0 ? mix(a,b,stage) : mix(b,c,stage-1.0);
    }

    float tubeSegment(float2 point,float2 a,float2 b) {
        float2 delta = b-a;
        return length(point-a-delta*clamp(dot(point-a,delta)/max(.0001,dot(delta,delta)),0.0,1.0));
    }

    float tubeBox(float2 p,float2 halfSize,float radius) {
        float2 q = abs(p)-halfSize+radius;
        return min(max(q.x,q.y),0.0)+length(max(q,float2(0.0)))-radius;
    }

    float4 tubeCartoonBody(float2 p,float tubeLength,float diameter,float h,float3 tint,
        texture2d<float> energy,float stage,float theme,float time,float aa) {
        float2 halfSize = float2(tubeLength,diameter)*.5;
        float radius = min(6.5,diameter*.25);
        float distance = tubeBox(p,halfSize,radius);
        if (distance > 10.0) return float4(0.0);
        float3 ink = float3(.075,.083,.095);
        float4 body = over(tint,exp(-max(0.0,distance)/2.5)*.065,float4(0.0));
        body = over(ink,1.0-smoothstep(-aa,aa,distance),body);
        float rim = 1.0-smoothstep(-aa,aa,tubeBox(p,halfSize-1.35,max(1.0,radius-1.35)));
        float3 metal = mix(float3(.26,.29,.33),float3(.70,.73,.76),
            1.0-smoothstep(-halfSize.y,halfSize.y,p.y));
        body = over(metal,rim,body);
        float capWidth = min(10.0,5.5+diameter*.10);
        float caps = smoothstep(halfSize.x-capWidth-.5,halfSize.x-capWidth+.5,abs(p.x))*rim;
        float3 yellow = mix(float3(.87,.49,.04),float3(1.0,.83,.26),
            1.0-smoothstep(-halfSize.y,halfSize.y,p.y));
        body = over(yellow,caps,body);
        float capLine = 1.0-smoothstep(.4,.9,abs(abs(p.x)-(halfSize.x-capWidth)));
        body = over(ink,capLine*rim,body);

        float2 windowSize = float2(halfSize.x-capWidth-2.0,max(2.0,halfSize.y-3.5));
        float window = 1.0-smoothstep(-aa,aa,tubeBox(p,windowSize,2.7));
        body = over(ink,window,body);
        float2 innerSize = max(float2(1.0),windowSize-1.15);
        float interior = 1.0-smoothstep(-aa,aa,tubeBox(p,innerSize,1.7));
        // Each current spans the whole meter. Independent velocities weave
        // together without folding the texture or splitting it at the center.
        float glint = pow(max(0.0,cos(p.x*.14-p.y*.24-time*4.0)),10.0);
        float band = 1.0-smoothstep(-innerSize.y,innerSize.y,p.y);
        float3 filled = mix(tint*.53,mix(tint,float3(1.0),.32),band);
        filled = mix(filled,mix(tint,float3(1.0),.70),glint*.38);
        filled = tubeWarm(filled,smoothstep(.84,1.0,h)*(.12+.38*glint));
        float2 flowUV = float2(fract(p.x/tubeLength*.875-time*.36),.375+p.y/diameter*.25);
        flowUV.y += sin(p.x*.07-time*3.0)*.003;
        float4 stream = tubeMaterial(energy,flowUV,1.0,stage,theme);
        float2 secondUV = float2(fract(p.x/tubeLength*1.14+time*.47+.42),.75-flowUV.y);
        stream = mix(stream,tubeMaterial(energy,secondUV,1.0,stage,theme),.24);
        float3 plasma = stream.rgb/max(.08,stream.a);
        plasma = tubeWarm(plasma,smoothstep(.84,1.0,h)*(.14+.26*glint));
        float3 cellColor = mix(filled*(.78+.22*h),plasma,min(.84,stream.a));
        body = over(cellColor,interior,body);
        float clock = time*2.4,epoch = floor(clock);
        float morph = smoothstep(.04,.96,fract(clock));
        for (int line=0; line<3; ++line) {
            float id = float(line),strand = 1e4;
            float2 a = float2(-innerSize.x,(id-1.0)*innerSize.y*.40);
            for (int j=1; j<=9; ++j) {
                float v = float(j)/9.0;
                float seed = id*53.1+float(j)*17.7;
                float noise = mix(hash(seed+epoch*11.9),hash(seed+(epoch+1.0)*11.9),morph)*2.0-1.0;
                float y = (id-1.0)*innerSize.y*.38+noise*innerSize.y*.40;
                float2 b = float2(mix(-innerSize.x,innerSize.x,v),y);
                strand = min(strand,tubeSegment(p,a,b));
                a = b;
            }
            float packet = pow(max(0.0,cos(p.x*.18-time*(4.5+id*.23)+id*2.1)),10.0);
            float strength = (.10+.12*h+.24*packet)*interior;
            body = over(tint,exp(-strand/(1.1+.55*h))*strength*.30,body);
            float core = (1.0-smoothstep(.18,.62+aa,strand))*strength;
            float3 current = tubeWarm(mix(tint,float3(1.0),.82),
                smoothstep(.84,1.0,h)*(.10+.45*packet));
            body = over(current,core,body);
        }
        float highlight = (1.0-smoothstep(.15,.65,abs(p.y+halfSize.y-2.0)))
            *(1.0-smoothstep(halfSize.x-6.0,halfSize.x-3.0,abs(p.x)));
        body = over(float3(1.0,.97,.84),highlight*.55,body);
        float bolt = length(float2(abs(p.x)-(halfSize.x-capWidth*.50),p.y));
        body = over(ink,(1.0-smoothstep(.65,1.1,bolt))*caps,body);
        return body;
    }

    float4 tubeHamsterCell(texture2d<float> atlas,float2 uv,float frame,
        constant LightningUniforms &l) {
        if (any(uv < float2(0.0)) || any(uv > float2(1.0))) return float4(0.0);
        constexpr sampler linearSampler(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 grid = l.hamsterAtlas.xy;
        float2 halfTexel = grid/float2(atlas.get_width(),atlas.get_height())*.5;
        uv = clamp(uv,halfTexel,1.0-halfTexel);
        float2 cell = float2(fmod(frame,grid.x),floor(frame/grid.x));
        return atlas.sample(linearSampler,(cell+uv)/grid);
    }

    float4 tubeHamsterFrame(texture2d<float> atlas,float2 uv,float frame,
        constant LightningUniforms &l) {
        float current = floor(frame),blend = fract(frame);
        float4 first = tubeHamsterCell(atlas,uv,current,l);
        if (blend < .0001) return first;
        // Every supplied clip has 24 frames. Its final frame blends back to its
        // own first frame, never into the next speed tier's artwork.
        float start = floor(current/24.0)*24.0;
        float next = start+fmod(current-start+1.0,24.0);
        return mix(first,tubeHamsterCell(atlas,uv,next,l),blend);
    }

    float4 tubeHamster(texture2d<float> atlas,float2 uv,float3 frames,float h,
        constant LightningUniforms &l) {
        // Narrow transition bands around 60 and 140 tok/s keep the aligned
        // wheels continuous while each GIF retains its own original cadence.
        float fast = smoothstep(.385,.445,h),turbo = smoothstep(.79,.845,h);
        if (fast < .0001) return tubeHamsterFrame(atlas,uv,frames.x,l);
        if (turbo > .9999) return tubeHamsterFrame(atlas,uv,frames.z,l);
        float4 middle = tubeHamsterFrame(atlas,uv,frames.y,l);
        if (fast < .9999) return mix(tubeHamsterFrame(atlas,uv,frames.x,l),middle,fast);
        if (turbo > .0001) return mix(middle,tubeHamsterFrame(atlas,uv,frames.z,l),turbo);
        return middle;
    }

    // Short rooted discharges visually suspend the tube beneath the notch.
    // A new pair of attachment points is chosen per strike, then stays attached
    // for its lifetime; small charge packets run upward through the gap.
    float4 tubeSuspension(float2 p,float h,float3 tint,constant Uniforms &u,
        constant LightningUniforms &l,constant LightningDischarge *events,
        float2 center,float diameter,float tubeLength,float2 rotation) {
        if (l.shape.z < .0001) return float4(0.0);
        float top = u.notchOrigin.y+u.notchSize.y;
        float lowest = center.y-diameter*.5+abs(rotation.y)*tubeLength*.5+4.0;
        if (p.y < top-1.0 || p.y > lowest) return float4(0.0);
        float4 field = float4(0.0);
        float aa = .55/u.pixelScale;
        for (int i=0; i<4; ++i) {
            LightningDischarge event = events[i+2];
            float age = event.timing.x,id = event.timing.w;
            float pulse = tubeDischargeEnvelope(event.timing);
            float gate = (i < 2 ? 1.0 : smoothstep(.28,.85,h))*l.shape.z*pulse;
            if (gate < .002) continue;
            float x0 = u.notchOrigin.x+u.notchSize.x*(.5+event.shape.x);
            float localX = x0-(u.notchOrigin.x+u.notchSize.x*.5)+event.shape.w*10.0;
            float2 terminal = center+tubeRotate(float2(localX,-diameter*.5+.7),rotation);
            float x1 = terminal.x,bottom = terminal.y;
            float gapScale = min(1.4,max(.3,(bottom-top)/13.7));
            float clock = age*14.0,epoch = floor(clock);
            float blend = smoothstep(.08,.92,fract(clock));
            float2 a = float2(x0,top+.12);
            float2 forkRoot = mix(a,float2(x1,bottom),.6);
            float distance = 1000.0;
            for (int j=1; j<=5; ++j) {
                float v = float(j)/5.0;
                float seed = id+float(j)*17.3;
                float kink = mix(hash(seed+epoch*43.7),hash(seed+(epoch+1.0)*43.7),blend)*2.0-1.0;
                float x = mix(x0,x1,v)+sin(v*M_PI_F)*kink*(1.5+2.2*h)*gapScale;
                float2 b = float2(x,mix(top+.12,bottom,v));
                distance = min(distance,tubeSegment(p,a,b));
                if (j == 3) forkRoot = b;
                a = b;
            }
            float chargeY = mix(bottom,top,clamp(age/event.timing.y,0.0,1.0));
            float charge = exp(-pow((p.y-chargeY)/2.0,2.0));
            float strength = min(.96,gate*(.56+.26*h+.20*charge));
            float core = (1.0-smoothstep(.22+.18*h-aa,.35+.22*h+aa,distance))*strength;
            float glow = exp(-distance/(.75+.45*h))*strength*.18;
            field = over(tint,glow,field);
            if (u.motion.z > .5) {
                float edge = (1.0-smoothstep(.65,1.35,distance))*strength*.35;
                field = over(tint*.28,edge,field);
            }
            field = over(mix(tint,float3(1.0),.78),core,field);
            float2 forkTip = forkRoot+float2(event.shape.z*(2.8+2.3*h)*event.shape.y,-2.5)*gapScale;
            float branchDistance = tubeSegment(p,forkRoot,forkTip);
            float branchFade = 1.0-clamp(length(p-forkRoot)/length(forkTip-forkRoot),0.0,1.0);
            float branch = (1.0-smoothstep(.12,.40+aa,branchDistance))*branchFade*strength*.65;
            field = over(mix(tint,float3(1.0),.60),branch,field);
            float contact = exp(-pow(length(p-float2(x0,top+.25)),2.0)/1.4)
                +exp(-pow(length(p-float2(x1,bottom)),2.0)/1.8);
            field = over(mix(tint,float3(1.0),.85),min(.35,contact*gate*.28),field);
        }
        return field;
    }

    fragment float4 lightningFragment(Vertex in [[stage_in]],constant Uniforms &u [[buffer(0)]],
        constant LightningUniforms &l [[buffer(1)]],
        constant LightningDischarge *events [[buffer(2)]],
        texture2d<float> hamsters [[texture(3)]],texture2d<float> leaks [[texture(4)]],
        texture2d<float> energy [[texture(5)]]) {
        if (u.visibility < .0001) return float4(0.0);
        float2 p = in.uv*u.viewport;
        float aa = .65/u.pixelScale;
        float outside = smoothstep(-aa,aa,rim(p,u).y);
        float3 anchor = float3(.010,.013,.018);
        if (outside < .0001) return float4(anchor,1.0)*u.drawsAnchor*u.visibility;

        float h = clamp(u.heat,0.0,1.0),stage = tubeStage(h);
        float overheat = smoothstep(.84,1.0,h);
        float theme = u.motion.z > .5 ? 1.0 : 0.0;
        float tubeLength = u.notchSize.x*(.88+.30*h);
        float diameter = (18.0+18.0*h)*l.shape.x;
        float2 center = float2(u.notchOrigin.x+u.notchSize.x*.5,
            u.notchOrigin.y+u.notchSize.y+l.shape.y+diameter*.5)+l.pose.xy;
        float2 rotation = float2(cos(l.pose.z),sin(l.pose.z));
        float2 bodyPoint = tubeRotate(p-center,float2(rotation.x,-rotation.y));
        float2 local = bodyPoint/float2(tubeLength,diameter);
        float2 uv = float2(.5+local.x*448.0/512.0,.375+local.y*64.0/256.0);
        float3 tint = stage < 1.0
            ? mix(float3(.77,.86,1.0),float3(.05,.43,1.0),stage)
            : mix(float3(.05,.43,1.0),float3(.64,.17,1.0),stage-1.0);
        tint = mix(tint,float3(1.0,.12,.36),overheat*.28);
        float4 result = float4(0.0);
        float spriteSize = l.hamsterLeft.w;
        float gap = l.shape.w;
        // Large pets may lower slightly to keep all smoke and sparks on-screen.
        float spriteDrop = max(0.0,3.0+abs(rotation.y)*(tubeLength*.5+gap+spriteSize)
            -center.y+l.hamsterAtlas.w*spriteSize);
        // Short outlined leads join each supplied generator to the meter.
        for (int side=0; side<2; ++side) {
            float sign = side == 0 ? -1.0 : 1.0;
            float2 a = float2(sign*(tubeLength*.5-1.0),0.0);
            float2 b = float2(sign*(tubeLength*.5+gap+3.0),spriteSize*.18+spriteDrop*.55);
            float2 c = float2(sign*(tubeLength*.5+spriteSize*.16+gap),spriteSize*.28+spriteDrop);
            float wire = min(tubeSegment(bodyPoint,a,b),tubeSegment(bodyPoint,b,c));
            result = over(float3(.075,.083,.095),1.0-smoothstep(1.15,1.65,wire),result);
            result = over(float3(1.0,.73,.12),1.0-smoothstep(.35,.75,wire),result);
        }
        float4 meter = tubeCartoonBody(bodyPoint,tubeLength,diameter,h,tint,energy,stage,theme,u.time,aa);
        result = meter+result*(1.0-meter.a);
        for (int group=0; group<2; ++group) {
            if (l.shape.z < .0001) break;
            LightningDischarge event = events[group];
            float age = event.timing.x,seed = event.timing.w;
            float discharge = tubeDischargeEnvelope(event.timing);
            float strength = (group == 0 ? .48+.52*h : smoothstep(.26,.80,h))*l.shape.z;
            float2 root = tubeLeakRoot(stage,group);
            float2 target = float2(.5+event.shape.x*448.0/512.0,root.y);
            float2 metric = float2(tubeLength*512.0/448.0,diameter*4.0);
            float2 slant = float2(cos(event.shape.w),sin(event.shape.w));
            float2 leakOffset = tubeRotate((uv-target)*metric,float2(slant.x,-slant.y));
            leakOffset /= float2(event.shape.z*(.78+.28*hash(seed+8.3)),event.shape.y);
            float2 leakUV = root+leakOffset/metric;
            // A very small flutter follows the burst, always rooted on the shell.
            leakUV.x += sin(leakUV.y*61.0+seed+age*50.0)*.0016
                *smoothstep(.01,.18,abs(uv.y-root.y));
            float distance = length((leakUV-root)*float2(512.0,256.0));
            float reach = 14.0+200.0*min(1.0,age/.024);
            float leader = 1.0-smoothstep(reach,reach+12.0,distance);
            float opacity = min(1.0,discharge*strength)*leader;
            float4 arc = tubeMaterial(leaks,leakUV,float(group),stage,theme)*opacity;
            arc.rgb = min(float3(arc.a),tubeWarm(arc.rgb,overheat*(.42+.24*discharge))*1.12);
            result = arc+result*(1.0-arc.a);

            float2 rootPoint = center+tubeRotate((target-float2(.5,.375))*metric,rotation);
            float pressure = smoothstep(-.055,-.01,age)*(1.0-smoothstep(0.0,.018,age))
                *event.timing.z*strength;
            float rootDistance = length(p-rootPoint);
            float flare = exp(-rootDistance*rootDistance/3.5)
                *(pressure*.12+discharge*strength*.24);
            float3 flareTint = mix(tint,float3(1.0,.16,.42),overheat*.60);
            result = over(mix(flareTint,float3(1.0),.65),flare,result);

            // A handful of short-lived particles detach from the leaking seam.
            for (int i=0; i<4; ++i) {
                float id = float(i)+float(group)*13.0;
                float particleAge = age-float(i)*.018;
                float life = min(event.timing.y,.17+.12*hash(id+seed));
                if (particleAge < 0.0 || particleAge > life) continue;
                float sign = group == 0 ? 1.0 : -1.0;
                float2 velocity = float2((hash(id+seed*7.9)-.5)*24.0*event.shape.z,
                    sign*(14.0+hash(id+seed+83.7)*26.0))*(.4+.6*h)*event.shape.y;
                velocity = tubeRotate(tubeRotate(velocity,slant),rotation);
                float2 head = rootPoint+velocity*particleAge*3.0
                    +float2(0.0,30.0*particleAge*particleAge);
                float2 tail = head-velocity*.025;
                float d = tubeSegment(p,tail,head);
                float opacity = min(1.0,(1.0-particleAge/life)*strength*discharge);
                float spark = (1.0-smoothstep(.10,.40+aa,d))*opacity*.75;
                result = over(mix(flareTint,float3(1.0),.65),spark,result);
            }
        }

        float below = p.y-u.notchOrigin.y-u.notchSize.y;
        float margin = min(p.x,u.viewport.x-p.x);
        float mask = smoothstep(.5,2.5,below)*smoothstep(1.0,4.0,margin)
            *(1.0-smoothstep(u.viewport.y-24.0,u.viewport.y-12.0,p.y));
        result *= mask;
        float4 suspension = tubeSuspension(p,h,tint,u,l,events,center,diameter,tubeLength,rotation);
        result += suspension*(1.0-result.a);
        float2 leftUV = float2((bodyPoint.x+tubeLength*.5+gap+spriteSize)/spriteSize,
            (bodyPoint.y-spriteDrop)/spriteSize+l.hamsterAtlas.w);
        float2 rightUV = float2(1.0-(bodyPoint.x-tubeLength*.5-gap)/spriteSize,
            (bodyPoint.y-spriteDrop)/spriteSize+l.hamsterAtlas.w);
        float4 left = tubeHamster(hamsters,leftUV,l.hamsterLeft.xyz,h,l);
        float4 right = tubeHamster(hamsters,rightUV,l.hamsterRight.xyz,h,l);
        result = left+result*(1.0-left.a);
        result = right+result*(1.0-right.a);
        result *= smoothstep(0.0,2.0,min(margin,min(p.y,u.viewport.y-p.y)));
        result.rgb = result.rgb*outside+anchor*(1.0-outside)*u.drawsAnchor;
        result.a = result.a*outside+(1.0-outside)*u.drawsAnchor;
        return result*u.visibility;
    }
    """#
}
