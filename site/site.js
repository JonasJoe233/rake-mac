/* 官网：文案来自 strings.json（和 App 同一份），See it. 一段的卵石图用 pebbles.js 现场画 */
let DICT={}, LANG="en", VERSION="0.1.0";
const $=s=>document.querySelector(s);
const REDUCE=matchMedia("(prefers-reduced-motion: reduce)").matches;
function T(k,v){let s=(DICT[LANG]&&DICT[LANG][k])||(DICT.en&&DICT.en[k])||k; for(const n in (v||{})) s=s.split("{"+n+"}").join(v[n]); return s;}
function pickLang(){
  const q=new URLSearchParams(location.search).get("lang"); if(q&&DICT[q]) return q;
  try{const s=localStorage.getItem("rake-lang"); if(s&&DICT[s]) return s;}catch(e){}
  return /^zh/i.test(navigator.language||"")?"zh-Hans":"en";  // 浏览器首选语言是中文就用简体中文
}
function applyText(){
  document.documentElement.lang=LANG;
  document.title=T("site.title");
  document.querySelector('meta[name="description"]').setAttribute("content",T("site.description"));
  // og 标签和 title、description 同源。抓取方不跑脚本，读的是 index.html 里写好的英文值
  document.querySelector('meta[property="og:title"]').setAttribute("content",T("site.title"));
  document.querySelector('meta[property="og:description"]').setAttribute("content",T("site.description"));
  document.querySelectorAll("[data-t]").forEach(e=>e.textContent=T(e.dataset.t));
  document.querySelectorAll("[data-t-alt]").forEach(e=>e.alt=T(e.dataset.tAlt));
  document.querySelectorAll("[data-t-aria]").forEach(e=>e.setAttribute("aria-label",T(e.dataset.tAria)));
  // 标语按句换行：英文两句两行，中文一句一行
  document.querySelectorAll("[data-lines]").forEach(e=>{e.textContent=""; T(e.dataset.t).split(/(?<=[.!?])\s+/).forEach(s=>{const p=document.createElement("span"); p.textContent=s; e.appendChild(p);});});
  $("#meta").textContent=T("site.meta",{v:VERSION});
  $("#lang").textContent=LANG==="en"?"中文":"English";
  $("#art").setAttribute("aria-label",T("site.see.b"));
}
$("#lang").onclick=()=>{LANG=LANG==="en"?"zh-Hans":"en"; try{localStorage.setItem("rake-lang",LANG);}catch(e){} applyText(); if(PLAYED) draw(1);};
$("#copy").onclick=async()=>{
  const b=$("#copy");
  try{await navigator.clipboard.writeText($("#cmd").textContent);}catch(e){const r=document.createRange(); r.selectNodeContents($("#cmd")); getSelection().removeAllRanges(); getSelection().addRange(r);}
  b.textContent=T("site.copied"); setTimeout(()=>b.textContent=T("site.copy"),1600);
};

/* ===== 卵石动画：一整块裂成卵石，几块缓存被选中，变成耙纹。滚到 See it. 才开始 ===== */
const PICKED=["upd","npm","brew","ext","pip"];
let STONES=[], L=null, SIZE="";
const ease=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;
const clamp=t=>Math.max(0,Math.min(1,t));
function textW(s,px){let w=0;for(const ch of s)w+=/[　-鿿＀-￯]/.test(ch)?px:px*.56;return w;}
const G=v=>v<=0?"0 M":v<0.095?Math.max(1,Math.round(v*1024))+" M":(v>=10?v.toFixed(0):v.toFixed(1))+" G";
function setup(){
  const box=$("#art").getBoundingClientRect(), W=Math.max(200,Math.round(box.width)), H=Math.max(160,Math.round(box.height));
  STONES=demoStones(T);
  const key=W+"x"+H;
  if(!L||SIZE!==key){L=layout(STONES,W,H); SIZE=key;}
  const svg=$("#svg"); svg.setAttribute("viewBox",`0 0 ${W} ${H}`);
}
// p：0..1 动画进度。0–.2 整块，.2–.6 裂开、上色，.65–1 选中、耙纹出现
function draw(p){
  setup();
  const svg=$("#svg"); svg.innerHTML="";
  const crack=ease(clamp((p-.2)/.4)), pick=ease(clamp((p-.65)/.35)), labels=clamp((p-.55)/.25);
  if(crack<1){ // 还没裂完的整块
    const g=el("g",{class:"it k-tools",opacity:1-crack},svg);
    el("path",{class:"c",d:rounded(L.R,30)},g);
  }
  if(crack<=0) return;
  const cs=cells(L.sites,L.R,9*crack);
  STONES.forEach((s,i)=>{
    const P=mergeShort(cs[i],16); if(P.length<3||area(P)<40) return;
    const on=PICKED.includes(s.id)&&pick>0;
    const g=el("g",{class:`it k-${s.kind}${on&&pick>.15?" sel":""}`,opacity:crack},svg);
    el("path",{class:"c",d:rounded(P,radius(P))},g);
    if(s.kind==="free") rakes(g,P,11,Math.round(30*crack));
    else if(on) rakes(g,P,8,Math.round(4*pick));
    if(labels<=0) return;
    const xs=P.map(q=>q[0]), ys=P.map(q=>q[1]), bw=Math.max(...xs)-Math.min(...xs), bh=Math.max(...ys)-Math.min(...ys);
    const [cx,cy]=centroid(P), sz=G(s.size), px=13, glyph=PICK(s.tier)&&!(on&&pick>.15)?16:0;
    const t=el("g",{opacity:labels},g);
    if(bw*.8>textW(s.label,px)+glyph+12&&bh>46){
      el("text",{x:cx+glyph/2,y:cy-2},t).textContent=s.label;
      el("text",{x:cx,y:cy+16,class:"sz"},t).textContent=sz;
      if(glyph) mark(t,cx-textW(s.label,px)/2-glyph/2+2,cy-6.5,s.tier);
    }else if(bw*.8>textW(sz,px)+8&&bh>24){
      el("text",{x:cx,y:cy+5,class:"sz"},t).textContent=sz;
    }
  });
}
function play(){
  const reduce=matchMedia("(prefers-reduced-motion: reduce)").matches;
  if(reduce){draw(1); return;}
  const t0=performance.now(), D=3200;
  const step=now=>{const p=clamp((now-t0)/D); draw(p); if(p<1) requestAnimationFrame(step);};
  requestAnimationFrame(step);
}
let PLAYED=false;
function watchArt(){
  const go=()=>{PLAYED=true; play();};
  if(!("IntersectionObserver" in window)) return go();
  const io=new IntersectionObserver(es=>{if(es.some(e=>e.isIntersecting)){io.disconnect(); go();}},{threshold:.35});
  io.observe($("#art"));
}
let rt; addEventListener("resize",()=>{clearTimeout(rt); rt=setTimeout(()=>{if(PLAYED) draw(1);},150);});

/* ===== 视频：静音自动播放；点声音开关取消静音并从 0 秒播；滚出视口暂停，回来再播 ===== */
const V=$("#promo"), SND=$("#snd");
let VIS=false, RESUME=!REDUCE;
SND.onclick=()=>{
  if(V.muted){V.muted=false; V.currentTime=0; V.play().catch(()=>{}); SND.dataset.t="site.video.soundOff";}
  else{V.muted=true; SND.dataset.t="site.video.soundOn";}
  SND.textContent=T(SND.dataset.t);
};
if("IntersectionObserver" in window){
  new IntersectionObserver(([e])=>{
    VIS=e.isIntersecting;
    if(!VIS){if(!V.paused) RESUME=true; V.pause();}
    else if(RESUME){RESUME=false; V.play().catch(()=>{});}
  },{threshold:.25}).observe(V);
  V.addEventListener("play",()=>{if(!VIS){V.pause(); RESUME=true;}}); // 自动播放晚于观察回调时，屏外也别播
}

/* ===== 入场：滚到时上移 + 淡入，只放一次（html.anim 在减少动态时不加） ===== */
if(document.documentElement.classList.contains("anim")){
  const ro=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add("in"); ro.unobserve(e.target);}}),{rootMargin:"0px 0px -8% 0px"});
  document.querySelectorAll(".rv").forEach(e=>ro.observe(e));
}

(async()=>{
  try{DICT=await (await fetch("strings.json")).json();}catch(e){DICT={};}
  try{VERSION=(await (await fetch("version.txt")).text()).trim()||VERSION;}catch(e){}
  LANG=pickLang(); applyText(); watchArt();
})();
