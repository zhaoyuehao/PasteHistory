import * as THREE from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {Spring} from './motion';
import type {Clip} from './store';
export type Anchor={x:number;y:number};
const seeds=[[-.78,7.75],[1.37,7.02],[1.92,6.05],[-2.04,5.58],[2.03,3.60],[-2.32,2.77],[2.16,1.98],[-1.70,1.25]];
export class TreeStage {
 private scene=new THREE.Scene();private camera=new THREE.PerspectiveCamera(38,1,.1,100);
 private renderer?:THREE.WebGLRenderer;private group=new THREE.Group();private anchors=seeds.map(([x,y])=>new THREE.Vector3(x,y,0));
 private cards=new Map<string,{el:HTMLButtonElement;clip:Clip;slot:number;life:Spring;scale:Spring;x:Spring;y:Spring}>();
 private ring=document.createElement('div');private rx=new Spring(0);private ry=new Spring(0);private rw=new Spring(150);private rh=new Spring(90);
 private selected:string|null=null;private preview=false;private visible=true;private frame=0;private last=0;private reduced=matchMedia('(prefers-reduced-motion: reduce)');
 private width=700;private height=700;private paperWidth=150;private dirty=true;private fallback:HTMLImageElement;
 onSelect:(id:string)=>void=()=>{};onDrag:(id:string)=>void=()=>{};onLayout:()=>void=()=>{};
 constructor(private host:HTMLElement){
  this.fallback=document.createElement('img');this.fallback.src=`${import.meta.env.BASE_URL}tree-fallback.png`;this.fallback.className='tree-fallback';this.fallback.alt='象牙白许愿树';host.append(this.fallback);
  this.group.rotation.y=-.24;this.scene.add(this.group);this.camera.position.set(0,4.15,16);this.scene.add(new THREE.HemisphereLight(0xfff9ec,0x708878,2.1));
  const key=new THREE.DirectionalLight(0xfff7df,3.4);key.position.set(-5,10,8);this.scene.add(key);const fill=new THREE.DirectionalLight(0xb9d5ce,1.5);fill.position.set(5,5,-3);this.scene.add(fill);
  this.ring.className='selection-ring';this.ring.setAttribute('aria-hidden','true');host.append(this.ring);
  try {
   if(new URLSearchParams(location.search).has('fallback'))throw new Error('Fallback preview');
   this.renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});this.renderer.setPixelRatio(Math.min(devicePixelRatio,1.8));this.renderer.setClearColor(0x000000,0);this.renderer.outputColorSpace=THREE.SRGBColorSpace;this.renderer.toneMapping=THREE.ACESFilmicToneMapping;host.prepend(this.renderer.domElement);
   this.renderer.domElement.addEventListener('webglcontextlost',e=>{e.preventDefault();this.fallback.hidden=false;this.renderer?.domElement.setAttribute('hidden','');});
   new GLTFLoader().load(`${import.meta.env.BASE_URL}tree.glb`,gltf=>{
    this.group.add(gltf.scene);this.group.updateMatrixWorld(true);this.snapAnchors(gltf.scene);this.fallback.hidden=true;this.dirty=true;this.wake();
   },undefined,()=>{this.renderer?.domElement.setAttribute('hidden','');this.fallback.hidden=false;});
  } catch {this.renderer?.dispose();this.renderer=undefined;}
  new ResizeObserver(()=>this.resize()).observe(host);
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(this.frame);this.frame=0;}else this.wake();});
  this.reduced.addEventListener('change',()=>this.wake());this.resize();
 }
 private snapAnchors(root:THREE.Object3D){
  const distance=seeds.map(()=>Infinity);root.updateMatrixWorld(true);
  root.traverse(o=>{if(!(o instanceof THREE.Mesh)||!o.name.toLowerCase().includes('tree'))return;const p=o.geometry.getAttribute('position');for(let i=0;i<p.count;i++){
   const v=new THREE.Vector3().fromBufferAttribute(p,i); // Exported vertices are already in the native scene's world coordinates.
   seeds.forEach(([x,y],j)=>{const z=-(.42*x*Math.sin(y*1.1)+.35*(Math.sin(x*1.7+y*.2)-Math.sin(y*.2)));const d=v.distanceToSquared(new THREE.Vector3(x,y,z));if(d<distance[j]){distance[j]=d;this.anchors[j]=v.clone();}});
  }});
 }
 private resize(){this.width=this.host.clientWidth;this.height=this.host.clientHeight;if(!this.width||!this.height)return;this.paperWidth=Math.max(122,Math.min(156,this.width*.235));this.host.style.setProperty('--paper-width',`${this.paperWidth}px`);this.camera.aspect=this.width/this.height;this.camera.position.z=Math.max(5.25/Math.tan(19*Math.PI/180),4.1/(Math.tan(19*Math.PI/180)*this.camera.aspect));this.camera.updateProjectionMatrix();this.camera.updateMatrixWorld();this.renderer?.setSize(this.width,this.height);this.dirty=true;this.wake();this.onLayout();}
 anchor(slot:number):Anchor{const p=this.anchors[slot].clone();if(this.renderer&&!this.fallback.hidden){/* Keep native fallback front view aligned while loading. */}else p.applyMatrix4(this.group.matrixWorld);p.project(this.camera);return {x:(p.x+1)*this.width/2,y:(1-p.y)*this.height/2};}
 rect(id:string){const c=this.cards.get(id);return c?.el.getBoundingClientRect();}
 render(entries:Clip[],selected:string|null,preview:boolean,visible:boolean){
  this.selected=selected;this.preview=preview;this.visible=visible;this.host.classList.toggle('tree-hidden',!visible);this.host.inert=!visible;
  const ids=new Set(entries.map(c=>c.id));this.cards.forEach((c,id)=>{if(!ids.has(id))c.life.target=0;});
  entries.forEach((clip,slot)=>{
   let c=this.cards.get(clip.id);
   if(!c){const el=document.createElement('button');el.type='button';el.className='paper';el.draggable=true;el.dataset.clipId=clip.id;
    el.addEventListener('click',()=>this.onSelect(clip.id));el.addEventListener('dragstart',e=>{e.dataTransfer?.setData('application/x-pastehistory',clip.id);e.dataTransfer?.setData('text/plain',clip.text);if(e.dataTransfer)e.dataTransfer.effectAllowed='copy';this.onDrag(clip.id);});
    c={el,clip,slot,life:new Spring(0),scale:new Spring(1),x:new Spring(this.anchor(slot).x-this.paperWidth/2),y:new Spring(this.anchor(slot).y+12)};this.cards.set(clip.id,c);this.host.append(el);
   }
   c.clip=clip;c.slot=slot;c.life.target=1;c.scale.target=clip.id===selected?1.075:1;
   c.el.setAttribute('aria-label',`${clip.source}：${clip.text}`);c.el.setAttribute('aria-pressed',String(clip.id===selected));c.el.classList.toggle('is-selected',clip.id===selected);c.el.classList.toggle('image-paper',clip.kind==='image');
   c.el.replaceChildren();const meta=document.createElement('span');meta.className='paper-meta';meta.textContent=`${String(slot+1).padStart(2,'0')} · ${clip.source}${clip.pinned?' · 已置顶':''}`;c.el.append(meta);
   if(clip.image){const img=document.createElement('img');img.src=clip.image;img.alt=clip.text;c.el.append(img);}else{const text=document.createElement('span');text.className='paper-text';text.textContent=clip.text;c.el.append(text);}
   const hint=document.createElement('span');hint.className='paper-hint';hint.textContent='单击展开  ·  拖动粘贴';c.el.append(hint);
  });this.wake();
 }
 private cardHeight(clip:Clip){const base=Math.max(55,Math.min(92,(this.height-70)/6));return base+(clip.kind==='image'?12:0);}
 private layoutCards(){const ys=this.anchors.map((_,i)=>this.anchor(i).y+12);const active=[...this.cards.values()].filter(c=>c.life.target===1);for(const lane of [[0,3,5,7],[1,2,4,6]]){let bottom=0;for(const slot of lane){const c=active.find(c=>c.slot===slot);if(!c)continue;ys[slot]=Math.max(ys[slot],bottom+10);bottom=ys[slot]+this.cardHeight(c.clip)*1.08;}}return ys;}
 wake(){if(!this.frame&&!document.hidden){this.last=performance.now();this.frame=requestAnimationFrame(t=>this.tick(t));}}
 private tick(now:number){
  this.frame=0;const dt=Math.min((now-this.last)/1000,.04);this.last=now;let active=false;
  const step=(s:Spring)=>{if(this.reduced.matches){s.value=s.target;s.velocity=0;}else s.step(dt);if(!s.settled)active=true;return s.value;};
  const positions=this.layoutCards();
  this.cards.forEach((c,id)=>{const life=step(c.life),scale=step(c.scale);if(c.life.target===0&&c.life.settled){c.el.remove();this.cards.delete(id);return;}
   const a=this.anchor(c.slot);const h=this.cardHeight(c.clip);c.x.target=a.x-this.paperWidth/2;c.y.target=positions[c.slot]??a.y+12;const x=step(c.x),y=step(c.y);
   c.el.style.height=`${h}px`;c.el.style.left=`${x}px`;c.el.style.top=`${y}px`;c.el.style.transform=`translateY(${(1-life)*16}px) rotate(${(c.slot%2?1.5:-1.5)*(1-life*.6)}deg) scale(${scale*(.85+.15*life)})`;
   c.el.style.opacity=String(this.preview&&id===this.selected?0:life);c.el.style.pointerEvents=c.life.target===0||(this.preview&&id===this.selected)?'none':'';c.el.tabIndex=c.life.target===0?-1:0;
   c.el.style.setProperty('--cord',`${Math.max(2,y-a.y)/scale}px`);
   if(id===this.selected){this.rx.target=x-(scale-1)*this.paperWidth/2;this.ry.target=y-(scale-1)*h/2;this.rw.target=this.paperWidth*scale;this.rh.target=h*scale;}
  });
  const x=step(this.rx),y=step(this.ry),w=step(this.rw),h=step(this.rh);this.ring.style.transform=`translate(${x}px,${y}px)`;this.ring.style.width=`${w+6}px`;this.ring.style.height=`${h+6}px`;this.ring.style.opacity=this.selected&&!this.preview&&this.visible?'1':'0';
  if(this.dirty&&this.renderer){this.renderer.render(this.scene,this.camera);this.dirty=false;}
  if(active)this.frame=requestAnimationFrame(t=>this.tick(t));
 }
}
