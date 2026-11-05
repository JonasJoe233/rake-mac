/* Rake 卵石图几何（App 与官网共用，官网的 site/pebbles.js 由 scripts/sync-site.sh 复制过去）
   加权 Voronoi（power diagram）：每块面积和占用成比例。
   绘图区不是矩形：朝右侧面板的一边是斜的，顶角和底角各让出一块三角形空地。 */
const NS="http://www.w3.org/2000/svg";
const PICK=t=>t==="auto"||t==="decide"; // 只有这两档能勾选、能交给引擎
const FLOOR_PICK=.015, FLOOR=.004;       // 能勾的项至少占 1.5% 面积，保证能点能读；其他项至少 0.4%
function clip(poly,a,b,c){ // 保留 a*x+b*y <= c
  const out=[], n=poly.length; if(!n) return out;
  for(let i=0;i<n;i++){
    const P=poly[i], Q=poly[(i+1)%n], fp=a*P[0]+b*P[1]-c, fq=a*Q[0]+b*Q[1]-c;
    if(fp<=0) out.push(P);
    if((fp<0&&fq>0)||(fp>0&&fq<0)){const t=fp/(fp-fq); out.push([P[0]+t*(Q[0]-P[0]),P[1]+t*(Q[1]-P[1])]);}
  }
  return out;
}
function area(p){let s=0;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length];s+=a[0]*b[1]-b[0]*a[1];}return Math.abs(s)/2;}
function perim(p){let s=0;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length];s+=Math.hypot(b[0]-a[0],b[1]-a[1]);}return s;}
function centroid(p){let x=0,y=0,s=0;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length],k=a[0]*b[1]-b[0]*a[1];s+=k;x+=(a[0]+b[0])*k;y+=(a[1]+b[1])*k;}
  if(Math.abs(s)<1e-9) return p.reduce((m,q)=>[m[0]+q[0]/p.length,m[1]+q[1]/p.length],[0,0]); return [x/(3*s),y/(3*s)];}
// 绘图区：左、上、下贴窗口留 14 的边；右边是一个尖角指向面板，上下各让出一块三角形
function region(W,H){
  const m=14, a=Math.min(170,Math.max(70,W*.15)), b=a*.62, ay=H*.56;
  return [[m,m],[W-m-a,m],[W-m,ay],[W-m-b,H-m],[m,H-m]];
}
function inside(R,x,y){ // R 为顺时针（屏幕坐标）凸多边形
  for(let i=0;i<R.length;i++){const a=R[i],b=R[(i+1)%R.length]; if((b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0])<0) return false;} return true;}
function cells(sites,R,gap){
  return sites.map((s,i)=>{
    let poly=R.slice();
    for(let j=0;j<sites.length&&poly.length;j++){ if(i===j) continue;
      const t=sites[j], nx=2*(t.x-s.x), ny=2*(t.y-s.y), len=Math.hypot(nx,ny); if(len<1e-9) continue;
      poly=clip(poly,nx,ny,(t.x*t.x+t.y*t.y-t.w)-(s.x*s.x+s.y*s.y-s.w)-gap/2*len);
    }
    return poly;
  });
}
const dedupe=P=>P.filter((p,i)=>{const q=P[(i-1+P.length)%P.length];return Math.hypot(p[0]-q[0],p[1]-q[1])>.5;});
function mergeShort(P,min){ // 合并太短的边，让每块保持 4 到 7 条边，圆角不被短边卡小
  P=dedupe(P);
  for(let guard=0;guard<20&&P.length>4;guard++){
    let k=-1,best=min;
    P.forEach((a,i)=>{const b=P[(i+1)%P.length],l=Math.hypot(b[0]-a[0],b[1]-a[1]); if(l<best){best=l;k=i;}});
    if(k<0) break;
    const a=P[k], j=(k+1)%P.length, b=P[j], mid=[(a[0]+b[0])/2,(a[1]+b[1])/2];
    P=P.map((p,i)=>i===k?mid:p).filter((p,i)=>i!==j);
  }
  while(P.length>7){ // 仍多于 7 条边：去掉最短边
    let k=0,best=Infinity; P.forEach((a,i)=>{const b=P[(i+1)%P.length],l=Math.hypot(b[0]-a[0],b[1]-a[1]); if(l<best){best=l;k=i;}});
    const a=P[k], j=(k+1)%P.length, b=P[j]; P=P.map((p,i)=>i===k?[(a[0]+b[0])/2,(a[1]+b[1])/2]:p).filter((p,i)=>i!==j);
  }
  return P;
}
function insetConvex(poly,d){
  let out=poly.slice(); const n=poly.length; if(n<3) return [];
  const sgn=Math.sign(poly.reduce((s,a,i)=>{const b=poly[(i+1)%n];return s+a[0]*b[1]-b[0]*a[1];},0))||1;
  for(let i=0;i<n&&out.length;i++){const a=poly[i],b=poly[(i+1)%n];
    let nx=(b[1]-a[1])*sgn, ny=-(b[0]-a[0])*sgn; const L=Math.hypot(nx,ny); if(L<1e-9) continue; nx/=L; ny/=L;
    out=clip(out,nx,ny,nx*a[0]+ny*a[1]-d);}
  return out;
}
function rounded(p,R){
  const n=p.length; if(n<3) return ""; let d="";
  for(let i=0;i<n;i++){
    const A=p[(i-1+n)%n],B=p[i],C=p[(i+1)%n];
    const l1=Math.hypot(B[0]-A[0],B[1]-A[1]), l2=Math.hypot(C[0]-B[0],C[1]-B[1]), r=Math.min(R,l1*.45,l2*.45);
    const p1=[B[0]+(A[0]-B[0])*r/(l1||1),B[1]+(A[1]-B[1])*r/(l1||1)], p2=[B[0]+(C[0]-B[0])*r/(l2||1),B[1]+(C[1]-B[1])*r/(l2||1)];
    d+=(i?"L":"M")+p1[0].toFixed(1)+","+p1[1].toFixed(1)+"Q"+B[0].toFixed(1)+","+B[1].toFixed(1)+" "+p2[0].toFixed(1)+","+p2[1].toFixed(1);
  }
  return d+"Z";
}
const radius=p=>Math.min(30,.45*2*area(p)/perim(p)); // 圆角 = min(30, 内切半径 × 0.45)
function rng(seed){return()=>{seed=(seed*16807)%2147483647;return(seed-1)/2147483646;};}
// 分区播种（绘图区比例）：可用靠右上贴着面板，工具左上，内容横穿下方，缓存在尖角附近（离勾选框最近），系统右下
const BAND={free:[.58,.86,.05,.42],tools:[.04,.55,.04,.55],content:[.04,.58,.62,.97],caches:[.62,.94,.4,.72],unknown:[.5,.72,.74,.97],system:[.72,.92,.76,.97]};
function layout(items,W,H,R){
  R=R||region(W,H); const A=area(R), rand=rng(11);
  const tot=items.reduce((s,x)=>s+x.size,0);
  const share=items.map(d=>Math.max(d.size/tot,PICK(d.tier)?FLOOR_PICK:FLOOR)), k=share.reduce((s,x)=>s+x,0);
  const cx=centroid(R);
  const sites=items.map((d,i)=>{const b=BAND[d.kind]||BAND.tools;
    let x=W*(b[0]+(b[1]-b[0])*rand()), y=H*(b[2]+(b[3]-b[2])*rand());
    for(let t=0;t<20&&!inside(R,x,y);t++){x=(x+cx[0])/2;y=(y+cx[1])/2;}
    return {x,y,w:A*share[i]/k*.1,t:A*share[i]/k};});
  for(let it=0;it<400;it++){
    const cs=cells(sites,R,0);
    sites.forEach((s,i)=>{const p=cs[i], a=p.length>2?area(p):0;
      if(a>0){const c=centroid(p); s.x=c[0]; s.y=c[1];}
      s.w*=Math.min(2,Math.max(.5,a>0?s.t/a:3)); if(s.w<1e-3) s.w=1e-3;});
    // 权重不超过到最近邻居距离的平方，否则站点会落到自己的格子外（Nocaj & Brandes 2012）
    sites.forEach((s,i)=>{let nn=Infinity; sites.forEach((t,j)=>{if(i!==j) nn=Math.min(nn,Math.hypot(s.x-t.x,s.y-t.y));}); s.w=Math.min(s.w,nn*nn);});
  }
  return {sites,R};
}
function el(tag,attrs,parent){const e=document.createElementNS(NS,tag);for(const k in attrs)e.setAttribute(k,attrs[k]);parent&&parent.appendChild(e);return e;}
function rakes(g,P,step,max){let p=P,k=0;while(k<max){p=insetConvex(p,step);if(p.length<3||area(p)<300)break;el("path",{class:"rk",d:rounded(p,Math.max(6,radius(p)))},g);k++;}}
function mark(g,x,y,tier){const k=el("g",{class:"gl"},g);
  if(tier==="auto") el("circle",{class:"f",cx:x,cy:y,r:4.5},k);
  else{el("circle",{class:"o",cx:x,cy:y,r:4.5},k); el("path",{class:"f",d:`M${x},${y-4.5}A4.5,4.5 0 0 0 ${x},${y+4.5}Z`},k);}}
/* 演示数据：一台普通 Mac 的样子。App 在浏览器里直接打开、官网首屏都用它 */
const DEMO=[
  ["free",38,"free"],["photo",54,"content"],["docs",31,"content"],["code",22,"content"],["chat",14,"content"],
  ["dl",6.4,"content","decide"],["trash",1.8,"content","manual"],
  ["apps",42,"tools"],["appdata",27,"tools"],["dot",12,"tools"],["llm",9,"tools"],["devenv",4,"tools"],
  ["sys",21,"system"],["sysdata",11,"system"],["swap",4,"system","manual"],
  ["upd",2.1,"caches","auto"],["npm",3.2,"caches","auto"],["brew",1.6,"caches","auto"],["ext",.9,"caches","auto"],
  ["pip",.6,"caches","auto"],["appc",6,"caches"],["unk",9,"unknown"]];
const RULE_IDS=new Set(["dl","trash","swap","upd","npm","brew","ext","pip","uv","crx","vsix","mid"]);
function demoStones(T){
  return DEMO.map(([id,size,kind,tier])=>{const r=RULE_IDS.has(id), k=r?"rule."+id:"stone."+id, s={id,size,kind,label:T(r?k+".label":k)};
    if(tier){s.tier=tier; s.why=T(k+".why",{used:"4.0 G",days:"9"}); s.cmd=T(k+".cmd",{n:"3"});} else if(id!=="free") s.why=T("why."+id);
    return s;});
}
