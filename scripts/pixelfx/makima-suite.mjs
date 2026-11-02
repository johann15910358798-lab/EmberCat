// Direct, continuous samples. PixelFX's 12 fps actor player is intentionally unused.
import { TAU, rng, wrap, smooth, ease } from '../../Vendor/PixelFX/core/math.js';
import { readFileSync } from 'node:fs';
import { humanGait, measurements } from './human-gait.mjs';

const designs = JSON.parse(readFileSync(new URL('./suite-design.json', import.meta.url), 'utf8'));

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

function sample(mode, config, phase) {
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
    Object.assign(row,humanGait(mode,config,phase));
    row.particles=contactDust(mode,config,phase);
  }
  return row;
}

const modes={};
for(const [mode,config] of Object.entries(designs)) {
  const rows=Array.from({length:config.frames+1},(_,i)=>({phase:i/config.frames}));
  modes[mode]={config,measurements:mode<'06'?measurements:null,
    poses:rows.slice(0,config.frames).map(row=>sample(mode,config,row.phase,row)),
    endpoint:sample(mode,config,1,rows[config.frames])};
}
console.log(JSON.stringify({fps:60,modes}));
