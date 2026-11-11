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
// 中文没有空格，浏览器会在任意两字之间折行，把「去哪了」「放心」拆开。这里列出允许折行的位置（每块开头的前缀），文案改了对不上就整句不分
const WRAP={"zh-Hans":{"site.h1":["先看清空间"]}};
// 只在窄屏插 <wbr>：宽屏一行放得下，拆成两段文字会让前半段有亚像素偏移
const NARROW=matchMedia("(max-width:719px)");
function segs(k,s){
  const w=NARROW.matches&&(WRAP[LANG]||{})[k]; if(!w) return [s];
  const out=[]; let r=s;
  for(const p of w){if(!r.startsWith(p)||r===p) return [s]; out.push(p); r=r.slice(p.length);}
  out.push(r); return out;
}
// 标语按句换行：英文两句两行，中文一句一行。中文句内按 WRAP 插 <wbr>，窄屏只在这些位置折
function splitLines(){
  document.querySelectorAll("[data-lines]").forEach(e=>{e.textContent=""; T(e.dataset.t).split(/(?<=[.!?])\s+/).forEach(s=>{const p=document.createElement("span"); segs(e.dataset.t,s).forEach((t,i)=>{if(i) p.appendChild(document.createElement("wbr")); p.appendChild(document.createTextNode(t));}); e.appendChild(p);});});
}
NARROW.addEventListener("change",()=>{if(DICT.en) splitLines();}); // 文案还没载入时不动
function applyText(){
  document.documentElement.lang=LANG;
  document.title=T("site.title");
  document.querySelector('meta[name="description"]').setAttribute("content",T("site.description"));
  // og 标签和 title、description 同源。抓取方不跑脚本，读的是 index.html 里写好的英文值
  document.querySelector('meta[property="og:title"]').setAttribute("content",T("site.title"));
  document.querySelector('meta[property="og:description"]').setAttribute("content",T("site.description"));
  document.querySelectorAll("[data-t]").forEach(e=>e.textContent=T(e.dataset.t,e.dataset.size&&{size:e.dataset.size}));
  document.querySelectorAll("[data-t-alt]").forEach(e=>e.alt=T(e.dataset.tAlt));
  document.querySelectorAll("[data-t-aria]").forEach(e=>e.setAttribute("aria-label",T(e.dataset.tAria)));
  splitLines();
  $("#meta").textContent=T("site.meta",{v:VERSION});
  $("#lang").textContent=LANG==="en"?"中文":"English";
  $("#art").setAttribute("aria-label",T("site.see.b"));
}
$("#lang").onclick=()=>{LANG=LANG==="en"?"zh-Hans":"en"; try{localStorage.setItem("rake-lang",LANG);}catch(e){} applyText(); if(PLAYED) draw(1); if(TK) tickRender(TK.sel);};
$("#copy").onclick=async()=>{
  const b=$("#copy");
  try{await navigator.clipboard.writeText($("#cmd").textContent);}catch(e){const r=document.createRange(); r.selectNodeContents($("#cmd")); getSelection().removeAllRanges(); getSelection().addRange(r);}
  b.textContent=T("site.copied"); setTimeout(()=>b.textContent=T("site.copy"),1600);
};

/* ===== 卵石图：「看清」一节裂开、上色、出标签；「勾选」一节同一张图，逐项勾上缓存 ===== */
const PICKED=["upd","npm","brew","ext","pip"];
let STONES=[];
const ease=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;
const clamp=t=>Math.max(0,Math.min(1,t));
function textW(s,px){let w=0;for(const ch of s)w+=/[　-鿿＀-￯]/.test(ch)?px:px*.56;return w;}
const G=v=>v<=0?"0 M":v<0.095?Math.max(1,Math.round(v*1024))+" M":(v>=10?v.toFixed(0):v.toFixed(1))+" G";
// layout 只和尺寸有关（和语言无关），按尺寸缓存。手机上两节的图一样大，算一次两节共用
const LAYOUTS=new Map();
function layoutFor(W,H){const k=W+"x"+H; if(!LAYOUTS.has(k)) LAYOUTS.set(k,layout(STONES,W,H)); return LAYOUTS.get(k);}
function boxOf(e){const b=e.getBoundingClientRect(); return [Math.max(200,Math.round(b.width)),Math.max(160,Math.round(b.height))];}
function label(g,P,s,on,op){
  const xs=P.map(q=>q[0]), ys=P.map(q=>q[1]), bw=Math.max(...xs)-Math.min(...xs), bh=Math.max(...ys)-Math.min(...ys);
  const [cx,cy]=centroid(P), sz=G(s.size), px=13, glyph=PICK(s.tier)&&!on?16:0;
  const t=el("g",{opacity:op},g);
  if(bw*.8>textW(s.label,px)+glyph+12&&bh>46){
    el("text",{x:cx+glyph/2,y:cy-2},t).textContent=s.label;
    el("text",{x:cx,y:cy+16,class:"sz"},t).textContent=sz;
    if(glyph) mark(t,cx-textW(s.label,px)/2-glyph/2+2,cy-6.5,s.tier);
  }else if(bw*.8>textW(sz,px)+8&&bh>24){
    el("text",{x:cx,y:cy+5,class:"sz"},t).textContent=sz;
  }
  return t;
}
// 选中的耙纹。pebbles.js 的 rakes() 按 App 的尺寸定了步长 8、面积下限 300，手机上的缓存块只有 300–900，一圈都画不出。
// 这里沿用它的 insetConvex、rounded，只把步长按块的内切半径缩放
function selRings(g,P){
  const r=2*area(P)/perim(P), step=Math.max(2.5,Math.min(8,r/4.5));
  let p=P; for(let k=0;k<4;k++){p=insetConvex(p,step); if(p.length<3||area(p)<40) break; el("path",{class:"rk",d:rounded(p,Math.max(3,radius(p)))},g);}
}
// 画出全部卵石，返回每块的节点，后面勾选时只改这一块
function paint(svg,L,crack,labels,sel){
  const out={}, cs=cells(L.sites,L.R,9*crack);
  STONES.forEach((s,i)=>{
    const P=mergeShort(cs[i],16); if(P.length<3||area(P)<40) return;
    const on=!!sel&&sel.has(s.id);
    const g=el("g",{class:`it k-${s.kind}${on?" sel":""}`,opacity:crack},svg);
    el("path",{class:"c",d:rounded(P,radius(P))},g);
    const rk=el("g",{},g); // 耙纹放在标签下面
    if(s.kind==="free") rakes(rk,P,11,Math.round(30*crack));
    else if(on) selRings(rk,P);
    out[s.id]={g,rk,P,s,t:labels>0?label(g,P,s,on,labels):null};
  });
  return out;
}
// 「看清」。p：0..1 动画进度。0–.25 整块，.25–.75 裂开、上色，.69–1 出标签。不选中，选中留给「勾选」
function draw(p){
  STONES=demoStones(T);
  const [W,H]=boxOf($("#art")), L=layoutFor(W,H), svg=$("#svg");
  svg.setAttribute("viewBox",`0 0 ${W} ${H}`); svg.innerHTML="";
  const crack=ease(clamp((p-.25)/.5)), labels=clamp((p-.69)/.31);
  if(crack<1){ // 还没裂完的整块
    const g=el("g",{class:"it k-tools",opacity:1-crack},svg);
    el("path",{class:"c",d:rounded(L.R,30)},g);
  }
  if(crack>0) paint(svg,L,crack,labels,null);
}
function play(){
  if(REDUCE){draw(1); return;}
  const t0=performance.now(), D=2560;
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

/* ===== 「勾选」：卡片 35% 进入视口后，每 450ms 勾一行，对应石头描边、出耙纹，「已选」累加到 8.4 GB。只放一次 ===== */
let TK=null, SUM=0, TW=null;
const sumOf=sel=>STONES.filter(s=>sel.has(s.id)).reduce((a,s)=>a+s.size,0);
function setSum(v){SUM=v; $("#tsum").textContent=T("site.tick.selected",{size:v.toFixed(1)+" GB"});}
function tickRender(sel){
  STONES=demoStones(T);
  const [W,H]=boxOf($("#tick .map")), L=layoutFor(W,H), svg=$("#tsvg");
  svg.setAttribute("viewBox",`0 0 ${W} ${H}`); svg.innerHTML="";
  TK={key:W+"x"+H,o:paint(svg,L,1,1,sel),sel};
  document.querySelectorAll("#tick li").forEach(li=>li.classList.toggle("on",sel.has(li.dataset.id)));
  setSum(TW?SUM:sumOf(sel));
}
function tickOne(id){
  TK.sel.add(id); $(`#tick li[data-id="${id}"]`).classList.add("on");
  const o=TK.o[id]; if(o){o.g.classList.add("sel"); selRings(o.rk,o.P); if(o.t){o.t.remove(); o.t=label(o.g,o.P,o.s,true,1);}}
  // 数字补间 300ms，每帧只改一个文本节点
  const from=SUM, to=sumOf(TK.sel), t0=performance.now();
  TW={to}; const tw=TW;
  const step=now=>{if(TW!==tw) return; const k=clamp((now-t0)/300); setSum(from+(to-from)*ease(k)); if(k<1) requestAnimationFrame(step); else TW=null;};
  requestAnimationFrame(step);
}
function tickPlay(){
  tickRender(new Set()); let i=0;
  const next=()=>{tickOne(PICKED[i++]); if(i<PICKED.length) setTimeout(next,450);};
  setTimeout(next,450);
}
function watchTick(){
  const card=$("#tick"), anim=document.documentElement.classList.contains("anim");
  if(!("IntersectionObserver" in window)) return tickRender(new Set(PICKED)); // 直接画最终状态
  // 离屏幕还有一屏时先把图画好（layout 最费时，放在动画开始之前）。减少动态时画的就是最终状态
  const pre=new IntersectionObserver(es=>{if(es.some(e=>e.isIntersecting)){pre.disconnect(); if(!TK) tickRender(anim?new Set():new Set(PICKED));}},{rootMargin:"100% 0px"});
  pre.observe(card);
  if(!anim) return;
  const io=new IntersectionObserver(es=>{if(es.some(e=>e.isIntersecting)){io.disconnect(); tickPlay();}},{threshold:.35});
  io.observe(card);
}

/* ===== 「核对」：审阅卡进入视口后 5 条每 250ms 出现一条，然后是按钮。html.anim 不在时 CSS 直接显示全部 ===== */
function watchRev(){
  if(!document.documentElement.classList.contains("anim")) return;
  const io=new IntersectionObserver(es=>{if(es.some(e=>e.isIntersecting)){io.disconnect();
    [...document.querySelectorAll("#rev .row"),$("#rev .act")].forEach((r,i)=>setTimeout(()=>r.classList.add("in"),i*250));}},{threshold:.35});
  io.observe($("#rev"));
}
let rt; addEventListener("resize",()=>{clearTimeout(rt); rt=setTimeout(()=>{
  if(PLAYED) draw(1);
  if(TK){const [W,H]=boxOf($("#tick .map")); if(TK.key!==W+"x"+H) tickRender(TK.sel);}
},150);});

/* ===== 视频：静音自动播放；点声音开关取消静音并从 0 秒播；滚出视口暂停，回来再播 ===== */
const V=$("#promo"), SND=$("#snd"), PLAY=$("#play");
let VIS=false, RESUME=!REDUCE, STARTED=false;
SND.onclick=()=>{
  if(V.muted){V.muted=false; V.currentTime=0; V.play().catch(()=>{}); SND.dataset.t="site.video.soundOff";}
  else{V.muted=true; SND.dataset.t="site.video.soundOn";}
  SND.textContent=T(SND.dataset.t);
};
// 自动播放被拦（低电量模式、省流量、App 内置浏览器）时给中间的播放按钮，不然只剩一张海报。不开原生控件：控件条的渐变会压住片子底部
function fallback(){if(REDUCE||!V.paused) return; PLAY.hidden=false;}
function tryPlay(){
  const t=setTimeout(()=>{if(!STARTED) fallback();},1500);
  V.play().catch(e=>{if(e&&e.name==="NotAllowedError"){clearTimeout(t); fallback();}});
}
V.addEventListener("playing",()=>{STARTED=true; PLAY.hidden=true;});
// 点击算用户手势，照样静音，声音只归开关管
PLAY.onclick=()=>{RESUME=false; V.play().catch(()=>{});};
// 点视频切换播放和暂停。停下时留个播放按钮，看得出是暂停而不是海报
if(!REDUCE) V.addEventListener("click",()=>{
  if(V.paused){RESUME=false; V.play().catch(()=>{PLAY.hidden=false;});}
  else{V.pause(); PLAY.hidden=false;}
});
if("IntersectionObserver" in window){
  new IntersectionObserver(([e])=>{
    VIS=e.isIntersecting;
    if(!VIS){if(!V.paused) RESUME=true; V.pause();}
    else if(RESUME){RESUME=false; tryPlay();}
  },{threshold:.25}).observe(V);
  V.addEventListener("play",()=>{if(!VIS){V.pause(); RESUME=true;}}); // 自动播放晚于观察回调时，屏外也别播
}else if(!REDUCE){VIS=true; tryPlay();}

/* ===== 手机下载：dmg 在手机上打不开，按钮改成把官网链接带到 Mac 上（分享，或者复制） ===== */
if(document.documentElement.classList.contains("nomac")){
  const URL_=document.querySelector('meta[property="og:url"]').content;
  const copy=async s=>{
    try{await navigator.clipboard.writeText(s); return true;}catch(e){}
    const a=document.createElement("textarea"); a.value=s; a.readOnly=true; a.style.cssText="position:fixed;opacity:0"; document.body.appendChild(a); a.select();
    let ok=false; try{ok=document.execCommand("copy");}catch(e){} a.remove(); return ok;
  };
  document.querySelectorAll(".btn").forEach(b=>{
    const s=b.querySelector("span"); s.dataset.t="site.downloadOnMac"; s.setAttribute("aria-live","polite");
    b.onclick=async ev=>{
      ev.preventDefault();
      if(navigator.share){
        try{await navigator.share({title:T("site.title"),url:URL_}); return;}catch(e){if(e&&e.name==="AbortError") return;}
      }
      // 复制也失败时（个别内置浏览器），把链接直接写在按钮上
      s.textContent=(await copy(URL_))?T("site.linkCopied"):URL_;
      clearTimeout(b._t); b._t=setTimeout(()=>s.textContent=T(s.dataset.t),2400);
    };
  });
}

/* ===== 入场：滚到时上移 + 淡入，只放一次（html.anim 在减少动态时不加） ===== */
if(document.documentElement.classList.contains("anim")){
  const ro=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add("in"); ro.unobserve(e.target);}}),{rootMargin:"0px 0px -8% 0px"});
  document.querySelectorAll(".rv").forEach(e=>ro.observe(e));
}

(async()=>{
  try{DICT=await (await fetch("strings.json")).json();}catch(e){DICT={};}
  try{VERSION=(await (await fetch("version.txt")).text()).trim()||VERSION;}catch(e){}
  LANG=pickLang(); applyText(); watchArt(); watchTick(); watchRev();
})();
