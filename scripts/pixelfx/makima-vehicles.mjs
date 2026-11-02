// PixelFX supplies deterministic per-particle randomness and smooth easing.
// The contact emitters and suspension are authored for EmberCat's source art.
import { TAU, rng, wrap, smooth, ease } from '../../Vendor/PixelFX/core/math.js';
import { readFileSync } from 'node:fs';

const designs = JSON.parse(readFileSync(new URL('./vehicle-design.json', import.meta.url), 'utf8'));
const frames = 144, duration = 2.4;

function sample(config, phase) {
  const t = phase * TAU;
  const center = (config.bounds[0] + config.bounds[2]) / 2;
  const contact = [18 + (config.wheels[0][0] - center) * config.scale, 18.92];
  const particles = [];
  for (let i = 0; i < config.dustCount; i++) {
    const random = rng(config.seed, i);
    const birth = (i + random.range(-0.12, 0.12)) / config.dustCount * duration;
    const life = config.dustLife * random.range(0.87, 1.0);
    const velocity = config.dustVelocity * random.range(0.9, 1.04);
    const lift = random.range(0.9, 1.45);
    const size = config.dustRadius * random.range(0.8, 1.1);
    const age = wrap(phase * duration - birth, duration);
    const a = age / life;
    if (a >= 1) continue;
    particles.push({
      id: i, kind: 'puff', age, life,
      x: contact[0] - velocity * age,
      y: contact[1] - 0.12 - lift * ease.outQuad(a),
      radius: 0.13 + size * ease.outQuad(a),
      opacity: smooth(0, 0.13, a) * (1 - smooth(0.32, 1, a)),
      squash: random.range(0.64, 0.82),
      lobe: random.range(0.7, 1.1),
    });
  }
  // A few short, low grit streaks establish the tire's contact with the road.
  for (let i = 0; i < 12; i++) {
    const random = rng(config.seed + 1, i);
    const life = random.range(0.27, 0.41);
    const age = wrap(phase * duration - i / 12 * duration, duration);
    const a = age / life;
    if (a >= 1) continue;
    particles.push({
      id: i + 100, kind: 'grit', age, life,
      x: contact[0] - random.range(11, 15) * age,
      y: contact[1] - random.range(0.1, 0.5) * Math.sin(Math.PI * a),
      radius: random.range(0.16, 0.32) * (1 + a),
      opacity: smooth(0, 0.12, a) * (1 - smooth(0.28, 1, a)) * 0.52,
    });
  }
  return {
    phase, contact, particles,
    wheelAngle: phase * TAU * config.turns,
    bodyY: config.bob * (0.8 * Math.sin(3 * t) + 0.2 * Math.sin(5 * t)),
    pitch: config.pitch * Math.PI / 180 * Math.sin(3 * t - 0.6),
    braidPhase: 2 * t - 0.5,
  };
}

const modes = {};
for (const [mode, config] of Object.entries(designs)) {
  modes[mode] = {config, poses: Array.from({length: frames}, (_, i) => sample(config, i / frames)),
    endpoint: sample(config, 1)};
}
console.log(JSON.stringify({frames, fps: 60, duration, modes}));
