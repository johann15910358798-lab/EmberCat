// Side-view character poses. Feet, weight shifts and arm arcs are authored for
// this two-legged drawing; no quadruped trajectory or projected 3D limbs.
import { TAU, wrap, smooth } from '../../Vendor/PixelFX/core/math.js';

const DEG = Math.PI / 180;
export const measurements = { thigh: 7.55, shin: 7.35, upper: 4.5, fore: 3.6 };
export const walking = { frames: 96, duration: 1.6, stride: 5.0, lift: 1.9, duty: .62 };

function curve(phase, keys) {
  const p = Math.max(0, Math.min(1, phase));
  const i = Math.min(keys.length - 2, Math.max(0, keys.findIndex((k, n) =>
    n + 1 < keys.length && p <= keys[n + 1][0])));
  const a = keys[i], b = keys[i + 1], u = smooth(a[0], b[0], p);
  return a.slice(1).map((v, n) => v + (b[n + 1] - v) * u);
}

function hermite(phase,keys) {
  const i=Math.min(keys.length-2,Math.max(0,keys.findIndex((k,n)=>n+1<keys.length&&phase<=keys[n+1][0])));
  const a=keys[i],b=keys[i+1],span=b[0]-a[0],u=(phase-a[0])/span;
  return (2*u**3-3*u*u+1)*a[1]+(u**3-2*u*u+u)*span*a[2]
    +(-2*u**3+3*u*u)*b[1]+(u**3-u*u)*span*b[2];
}

function periodicPath(phase,keys) {
  const points=keys.slice(0,-1).map((key,i,all)=>{
    const prev=i?all[i-1]:[all.at(-1)[0]-1,all.at(-1)[1]];
    const next=i+1<all.length?all[i+1]:[1,all[0][1]];
    return [...key,(next[1]-prev[1])/(next[0]-prev[0])];
  });
  points.push([1,points[0][1],points[0][2]]);
  return hermite(phase,points);
}

function foot(x, lift, pitch, support, phase, pivot = 0, height = 2.6) {
  const a = pitch * DEG;
  // Roll about the heel/toe contact, keeping that point on its ground plane.
  return { x: x + pivot - pivot * Math.cos(a) + height * Math.sin(a),
    lift, pitch, support, phase, groundX: x, pivot, soleHeight: height,
    ankleY: height * Math.cos(a) + pivot * Math.sin(a) + lift };
}

function step(p, config, running = false) {
  const { stride, lift, duty } = config;
  if (p < duty) {
    const u = p / duty;
    const pitch = running
      ? 22 * smooth(.53, 1, u)
      : -8 * (1 - smooth(0, .18, u)) + 18 * smooth(.68, 1, u);
    const pivot = pitch < 0 ? -1.0 : 3.8;
    return foot(stride * (1 - 2 * u), 0, pitch, true, p, pivot);
  }
  const u = (p - duty) / (1 - duty);
  const tangent = -2 * stride / duty * (1 - duty);
  const x = (2*u**3 - 3*u*u + 1)*-stride + (u**3 - 2*u*u + u)*tangent
    + (-2*u**3 + 3*u*u)*stride + (u**3 - u*u)*tangent;
  const pitch = curve(u, running
    ? [[0,22],[.25,12],[.65,-10],[1,0]]
    : [[0,18],[.25,13],[.65,-8],[1,-8]])[0];
  const pivot = 3.8 + (-1.0 - 3.8) * smooth(.12, .82, u);
  return foot(x, lift * Math.sin(Math.PI*u)**2, pitch, false, p, pivot);
}

function skate(p) {
  // Hold the leading skate under the weight, extend the other behind, then
  // recover it off the ground. This is a skating push, not walking in boots.
  const x=periodicPath(p,[[0,3.6],[.18,2.8],[.35,-.8],[.60,-6.6],[.74,-5.5],[.91,2.9],[1,3.6]]);
  const [lift,pitch]=curve(p,[[0,0,0],[.60,0,0],[.74,3.3,-27],[.91,.6,-5],[1,0,0]]);
  return foot(x,lift,pitch,p<=.60,p,0,3.3);
}

function skateboard(p) {
  // The rear/pushing foot clears the deck before settling into a two-foot glide.
  const keys = [[0,.4,0,0],[.24,-6.2,0,16],[.40,-6.3,3.7,-10],
    [.57,-2.7,2.2,0],[.82,-2.7,2.2,0],[.91,-.1,1.4,-6],[1,.4,0,0]];
  const [,lift,pitch] = curve(p,keys);
  const x=hermite(p,[[0,.4,-27.5],[.24,-6.2,-27.5],[.40,-6.3,19],
    [.57,-2.7,0],[.82,-2.7,0],[.94,1.1,0],[1,.4,-27.5]]);
  const push = foot(x,lift,pitch,p<.24,p,3.8*smooth(.10,.24,p)*(1-smooth(.24,.4,p)));
  push.onDeck = p >= .57 && p <= .82;
  const planted = foot(2.8,2.2,0,true,p);
  planted.onDeck = true;
  return { near: push, far: planted };
}

function leg(hip, ankle) {
  const [l1,l2] = [measurements.thigh,measurements.shin];
  const dx=ankle[0]-hip[0],dy=ankle[1]-hip[1],d=Math.hypot(dx,dy);
  if (d >= l1+l2 || d <= Math.abs(l1-l2))
    throw new Error(`Unreachable authored leg: ${JSON.stringify({hip,ankle,d})}`);
  const along=(l1*l1-l2*l2+d*d)/(2*d),h=Math.sqrt(l1*l1-along*along);
  // The drawing faces right. A single, fixed bend direction avoids knee flips.
  return [hip[0]+dx/d*along-dy/d*h,hip[1]+dy/d*along+dx/d*h,hip[2]];
}

function arm(shoulder, angle, bend) {
  const a=angle*DEG,b=(angle+bend)*DEG;
  const elbow=[shoulder[0]+measurements.upper*Math.sin(a),
    shoulder[1]-measurements.upper*Math.cos(a),shoulder[2]];
  const hand=[elbow[0]+measurements.fore*Math.sin(b),
    elbow[1]-measurements.fore*Math.cos(b),shoulder[2]];
  return { elbow, hand };
}

export function humanGait(mode,config,phase) {
  const p=wrap(phase,1),t=p*TAU;
  const running=mode==='03-run',rolling=mode==='04-rollers',boarding=mode==='05-board';
  let feet,hipY,pelvisX=0,lean;
  if(boarding) {
    feet=skateboard(p);
    [hipY,lean,pelvisX]=curve(p,[[0,17.1,18,.4],[.24,16.0,25,1.0],
      [.40,16.6,23,.7],[.57,17.6,20,.3],[.82,17.6,20,.3],[1,17.1,18,.4]]);
  } else if(rolling) {
    feet={near:skate(p),far:skate(wrap(p+.5,1))};
    hipY=16.0+.20*Math.cos(2*t);pelvisX=.15*Math.sin(t);lean=16;
  } else {
    feet={near:step(p,config,running),far:step(wrap(p+.5,1),config,running)};
    hipY=running?15.35+.85*Math.cos(2*t-TAU*.84)
      :16.8-.50*Math.cos(2*t-.38);
    lean=running?11+1.5*Math.sin(2*t):mode==='02-brisk'?5:2;
  }
  const a=lean*DEG,rotate=(x,y)=>[x*Math.cos(a)+y*Math.sin(a),-x*Math.sin(a)+y*Math.cos(a)];
  const pelvis=[pelvisX,hipY+1.7,0];
  const attach=(x,y,z=0)=>{const r=rotate(x,y);return [pelvis[0]+r[0],pelvis[1]+r[1],z];};
  const joints={pelvis,neck:attach(.4,7.6),hipN:[pelvisX-.5,hipY,.1],
    hipF:[pelvisX+.5,hipY,-.1],shoulderN:attach(-1.4,5.3,.1),
    shoulderF:attach(1.8,4.9,-.1)};
  for(const [side,key] of [['N','near'],['F','far']]) {
    const f=feet[key],z=joints['hip'+side][2];
    joints['ankle'+side]=[f.x,f.ankleY,z];
    joints['knee'+side]=leg(joints['hip'+side],joints['ankle'+side]);
    const sign=side==='N'?1:-1;
    let angle,bend;
    if(boarding) {angle=sign===1?-21-5*Math.sin(t):20+4*Math.sin(t);bend=sign===1?24:38;}
    else if(rolling) {angle=sign*-23*Math.cos(t)-7;bend=42+5*Math.sin(t)*sign;}
    else {angle=-sign*(running?40:mode==='02-brisk'?28:23)*Math.cos(t-.12);
      bend=running?82+8*sign*Math.sin(t):mode==='02-brisk'?34:18;}
    const solved=arm(joints['shoulder'+side],angle,bend);
    joints['elbow'+side]=solved.elbow;joints['hand'+side]=solved.hand;
  }
  return {phase:p,humanGait:true,mode,joints,...feet,bodyAngle:lean,
    headAngle:(running?2.5:rolling||boarding?1:0)+.35*Math.sin(2*t-.4),
    braidAngle:(running?7:rolling||boarding?6:1.5)+(running?2.5:1.4)*Math.sin(t-.8),
    wheelAngle:5*t,pose:{lean,pelvisX,hipY},particles:[]};
}
