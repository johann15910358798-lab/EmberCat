// Continuous walking, solved by PixelFX's fixed-length 3D skeleton.
// Sample the solver directly: the upstream act player deliberately holds at 12 fps.
import { skeleton } from '../../Vendor/PixelFX/core/rig.js';
import { readFileSync } from 'node:fs';

const TAU = Math.PI * 2;
const frames = 96;
const duration = 1.6;
// Python supplies the production cat's foot_path samples, including the end pose.
const { gait, samples } = JSON.parse(readFileSync(0, 'utf8'));
if (samples.length !== frames + 1) throw new Error('Expected 96 samples plus the loop endpoint');
const measurements = {
  pelvis: 19.3, spine1: 2.8, spine2: 3.6, neckUp: 1.0, headUp: 7.0,
  shoulderUp: -0.6, shoulderOut: 3.0, hipDown: 1.5, hipOut: 1.1,
  thigh: 8.0, shin: 7.8, upper: 4.7, fore: 3.7, turn: 0.5,
};

function sample({phase, near, far}) {
  const t = TAU * phase;
  const pose = {
    turn: 0.5, lean: 0.2, crouch: 0.15 + 0.08 * Math.cos(2*t),
    ffx: near.x, ffy: -(4.8 + near.lift), fbx: far.x, fby: -(4.8 + far.lift),
    fzz: 0.8, bzz: -0.8,
    fx: -0.8 - 3.5 * Math.cos(t), fy: -16.2 - 0.35 * Math.sin(t), fz: 1.5,
    bx: 1.8 + 3.5 * Math.cos(t), by: -16.2 + 0.35 * Math.sin(t), bz: -1.5,
  };
  const rig = skeleton(pose, measurements);
  return { phase, pose, joints: rig.joints, near, far };
}

const poses = samples.slice(0, frames).map(sample);
const end = sample(samples[frames]);
const seamError = Math.max(...Object.keys(end.joints).flatMap(key => end.joints[key].map((v,i) => Math.abs(v - poses[0].joints[key][i]))));
if (seamError > 1e-10) throw new Error(`Open loop: ${seamError}`);
for (const row of poses) {
  for (const point of Object.values(row.joints)) if (!point.every(Number.isFinite)) throw new Error('Non-finite joint');
  for (const [suffix, foot] of [['N',row.near],['F',row.far]]) {
    const ankle = row.joints[`ankle${suffix}`];
    if (Math.abs(ankle[0] - foot.x) > 1e-6 || Math.abs(ankle[1] + 3 + foot.lift) > 1e-6) {
      throw new Error(`Unreachable ${suffix} ankle at phase ${row.phase}`);
    }
  }
}
console.log(JSON.stringify({ frames, duration, fps: frames/duration, gait, measurements, seamError, poses }));
