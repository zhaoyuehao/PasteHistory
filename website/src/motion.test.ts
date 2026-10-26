import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Spring} from './motion';
test('reversing an unfinished animation preserves its state and reaches the latest target',()=>{const s=new Spring(0);s.target=1;for(let i=0;i<8;i++)s.step(1/60);const {value,velocity}=s;s.target=0;assert.equal(s.value,value);assert.equal(s.velocity,velocity);for(let i=0;i<300;i++){if(i%12===0&&i<100)s.target=s.target===0?1:0;s.step(1/60);assert.ok(Number.isFinite(s.value));}assert.equal(s.value,s.target);assert.equal(s.settled,true);});
test('long hidden-tab gap does not create an unstable jump',()=>{const s=new Spring(0);s.target=1;s.step(20);assert.ok(s.value>=0&&s.value<=1.2);for(let i=0;i<200;i++)s.step(1/120);assert.equal(s.value,1);});
