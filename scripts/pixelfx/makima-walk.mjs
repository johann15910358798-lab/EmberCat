import { humanGait, measurements, walking } from './human-gait.mjs';

const { frames,duration }=walking;
const poses=Array.from({length:frames},(_,i)=>humanGait('01-walk',walking,i/frames));
const endpoint=humanGait('01-walk',walking,1);
const seamError=Math.max(...Object.keys(endpoint.joints).flatMap(key=>
  endpoint.joints[key].map((v,i)=>Math.abs(v-poses[0].joints[key][i]))));
if(seamError>1e-10)throw new Error(`Open loop: ${seamError}`);
console.log(JSON.stringify({frames,duration,fps:60,gait:walking,measurements,seamError,poses,endpoint}));
