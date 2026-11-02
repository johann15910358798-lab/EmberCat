// Direct, continuous samples. PixelFX's 12 fps actor player is intentionally unused.
import { skeleton } from '../../Vendor/PixelFX/core/rig.js';
import { TAU, rng, wrap, smooth, ease } from '../../Vendor/PixelFX/core/math.js';
import { readFileSync } from 'node:fs';

const designs = JSON.parse(readFileSync(new URL('./suite-design.json', import.meta.url), 'utf8'));
const input = JSON.parse(readFileSync(0, 'utf8'));
const measurements = {
  pelvis:19.3, spine1:2.8, spine2:3.6, neckUp:1.0, headUp:7.0,
  shoulderUp:-0.6, shoulderOut:3.0, hipDown:1.5, hipOut:1.1,
  thigh:8.0, shin:7.8, upper:4.7, fore:3.7, turn:0.5,
};

function keyPath(phase, keys) {
  const p = wrap(phase, 1);
  const i = Math.max(0, keys.findIndex((k, n) => n + 1 < keys.length && p < keys[n + 1][0]));
  const a = keys[i], b = keys[i + 1], u = smooth(a[0], b[0], p);
  return {x:a[1]+(b[1]-a[1])*u, lift:a[2]+(b[2]-a[2])*u,
    pitch:a[3]+(b[3]-a[3])*u, support:p<0.22, phase:p};
}

function contactDust(mode, config, phase) {
  const recipes = {
    '03-run': {births:[0.02,0.52], life:0.38, radius:0.62, velocity:8.2, x:19.2},
    '04-rollers': {births:[0.27,0.32,0.77,0.82], life:0.40, radius:0.47, velocity:9.0, x:17.3},
    '05-board': {births:[0.04,0.11,0.18], life:0.48, radius:0.68, velocity:8.0, x:17.0},
    '06-bicycle': {births:[0,0.125,0.25,0.375,0.5,0.625,0.75,0.875], life:0.43, radius:0.46, velocity:8.5, x:13.3},
  };
  const r = recipes[mode];
  if (!r) return [];
  return r.births.flatMap((birth,i) => {
    const random = rng(3710 + Number(mode.slice(0,2)), i);
    const age = wrap(phase*config.duration-birth*config.duration, config.duration), a = age/r.life;
    if (a >= 1) return [];
    return [{id:i, kind:'puff', age, life:r.life,
      x:r.x-r.velocity*age, y:18.95-0.75*ease.outQuad(a), radius:0.09+r.radius*ease.outQuad(a),
      opacity:smooth(0,0.14,a)*(1-smooth(0.25,1,a))*0.65,
      squash:random.range(0.5,0.7),lobe:random.range(0.7,1.1)}];
  });
}

function solveLeg(hip, ankle, thigh=70, shin=81) {
  const dx=ankle[0]-hip[0],dy=ankle[1]-hip[1],d=Math.hypot(dx,dy);
  if (d >= thigh+shin || d <= Math.abs(thigh-shin)) throw new Error('Unreachable bicycle pedal');
  const along=(thigh*thigh-shin*shin+d*d)/(2*d), h=Math.sqrt(thigh*thigh-along*along);
  return [hip[0]+dx/d*along+dy/d*h,hip[1]+dy/d*along-dx/d*h];
}

function sample(mode, config, phase, feet) {
  const t=phase*TAU, row={phase,particles:contactDust(mode,config,phase)};
  if (mode === '06-bicycle') {
    const a=t*config.pedalTurns;
    row.bodyY=2.0*Math.sin(2*t)+1.5*Math.sin(t);
    row.wheelAngle=t*config.wheelTurns;
    row.braidPhase=t;
    row.legs=['N','F'].map((side,i)=>{
      const angle=a+i*Math.PI, pedal=[config.crank[0]+config.crankRadius*Math.cos(angle),
        config.crank[1]+config.crankRadius*Math.sin(angle)];
      const ankle=[pedal[0]-8,pedal[1]-20];
      const hip=[146+(i?-5:0),284+row.bodyY];
      return {side,pedal,ankle,hip,knee:solveLeg(hip,ankle)};
    });
  } else if (mode === '09-jetpack') {
    Object.assign(row,{bodyX:1.2*Math.sin(t),bodyY:3.8*Math.sin(t-0.35),
      pitch:0.6*Math.sin(t+0.3),braidPhase:2*t,legSway:5*Math.sin(t-0.6),
      plumeLength:60+7*Math.sin(5*t)+3*Math.sin(7*t),plumePhase:5*t});
    row.particles=Array.from({length:10},(_,i)=>{
      const random=rng(9011,i), life=random.range(0.4,0.62);
      const age=wrap(phase*config.duration-i/10*config.duration,config.duration),a=age/life;
      const cx=18+(config.emitter[0]-(config.bounds[0]+config.bounds[2])/2)*config.scale;
      const cy=18+(config.emitter[1]-config.bounds[3])*config.scale;
      return {id:i,kind:'puff',age,life,x:cx-1.9-7.1*age,y:cy+1.3+3.5*age,
        radius:0.12+0.65*ease.outQuad(Math.min(1,a)),opacity:a<1?smooth(0,0.15,a)*(1-smooth(0.3,1,a))*0.55:0,
        squash:0.64,lobe:1};
    }).filter(p=>p.opacity>0);
  } else {
    let {near,far}=feet;
    if(mode==='05-board') {
      near={x:2.7,lift:3.0,pitch:-13,support:true,phase};
      far=keyPath(phase,[[0,0.8,0,0],[0.22,-7.2,0,0],[0.44,-6.3,3.9,-24],
        [0.63,-1.8,3.2,-13],[0.78,-1.8,3.2,-13],[1,0.8,0,0]]);
    }
    const offset=mode==='04-rollers'?2:0;
    const pose={turn:0.5,lean:config.lean,crouch:config.crouch+0.16*Math.cos(2*t),
      ffx:near.x,ffy:-(4.8+near.lift+offset),fbx:far.x,fby:-(4.8+far.lift+offset),
      fzz:0.8,bzz:-0.8,
      fx:-0.8-config.armSwing*Math.cos(t),fy:-config.handHeight-0.4*Math.sin(t),fz:1.5,
      bx:1.8+config.armSwing*Math.cos(t),by:-config.handHeight+0.4*Math.sin(t),bz:-1.5};
    if(mode==='05-board') {
      pose.fx=-3.8-0.8*Math.cos(t);pose.bx=5.2+0.8*Math.cos(t);
      pose.fy=-18.7;pose.by=-19.8;
    }
    Object.assign(row,{pose,near,far,joints:skeleton(pose,measurements).joints,
      wheelAngle:5*t,braidAngle:config.braid+2.0*Math.sin(t-0.7)});
  }
  return row;
}

const modes={};
for(const [mode,config] of Object.entries(designs)) {
  const rows=input[mode] || Array.from({length:config.frames+1},(_,i)=>({phase:i/config.frames}));
  modes[mode]={config,measurements:mode<'06'?measurements:null,
    poses:rows.slice(0,config.frames).map(row=>sample(mode,config,row.phase,row)),
    endpoint:sample(mode,config,1,rows[config.frames])};
}
console.log(JSON.stringify({fps:60,modes}));
