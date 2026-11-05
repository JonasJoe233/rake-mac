/* 官网：文案来自 strings.json（和 App 同一份），首屏卵石图用 pebbles.js 现场画 */
let DICT={}, LANG="en", VERSION="0.1.0";
const $=s=>document.querySelector(s);
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
  document.querySelectorAll("[data-t]").forEach(e=>e.textContent=T(e.dataset.t));
  $("#meta").textContent=T("site.meta",{v:VERSION});
  $("#lang").textContent=LANG==="en"?"中文":"English";
  $("#art").setAttribute("aria-label",T("site.f3.t"));
}
$("#lang").onclick=()=>{LANG=LANG==="en"?"zh-Hans":"en"; try{localStorage.setItem("rake-lang",LANG);}catch(e){} applyText(); draw(1);};
$("#copy").onclick=async()=>{
  const b=$("#copy");
  try{await navigator.clipboard.writeText($("#cmd").textContent);}catch(e){const r=document.createRange(); r.selectNodeContents($("#cmd")); getSelection().removeAllRanges(); getSelection().addRange(r);}
  b.textContent=T("site.copied"); setTimeout(()=>b.textContent=T("site.copy"),1600);
};

/* ===== 首屏动画：一整块裂成卵石，几块缓存被选中，变成耙纹 ===== */
const PICKED=["upd","npm","brew","ext","pip"];
let STONES=[], L=null, SIZE="";
const ease=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;
const clamp=t=>Math.max(0,Math.min(1,t));
function textW(s,px){let w=0;for(const ch of s)w+=/[　-鿿＀-￯]/.test(ch)?px:px*.56;return w;}
const G=v=>v<0.095?Math.max(1,Math.round(v*1024))+" M":(v>=10?v.toFixed(0):v.toFixed(1))+" G";
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
let rt; addEventListener("resize",()=>{clearTimeout(rt); rt=setTimeout(()=>draw(1),150);});
(async()=>{
  try{DICT=await (await fetch("strings.json")).json();}catch(e){DICT={};}
  try{VERSION=(await (await fetch("version.txt")).text()).trim()||VERSION;}catch(e){}
  LANG=pickLang(); applyText(); play();
})();
