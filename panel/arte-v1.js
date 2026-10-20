'use strict';
// Arte pixel de la v1 (Codex, 17-oct): personajes, mascotas, plantas, estanterías, ciudad y sala completa.
// La v2.1 y v3 conservan su distribución y llaman a V1.* para dibujar con este nivel de detalle.
const V1 = (() => {
  const colors = { claude: '#dba08b', codex: '#88c3dd', agy: '#89c3a7' };
  const travel = [], flashes = {};
  const crown = null;
const R=(x,y,w,h,c)=>{ctx.fillStyle=c;ctx.fillRect(Math.round(x),Math.round(y),Math.round(w),Math.round(h));};
function text(s,x,y,size=10,color='#d8e1e7',align='left',maxW=null){ctx.font=`${size}px Consolas, monospace`;ctx.fillStyle=color;ctx.textAlign=align;ctx.textBaseline="alphabetic";ctx.fillText(String(s),Math.round(x),Math.round(y));
  if(typeof registrarTexto==='function'&&depurar){const w=ctx.measureText(String(s)).width;registrarTexto(s,align==='center'?x-w/2:align==='right'?x-w:x,y-size*.8,w,size,maxW);}}
function clipped(s,max){return String(s||'').length>max?String(s).slice(0,max-1)+'…':String(s||'');}
function plant(x,y,large=false){let z=large?1.5:1;ctx.save();ctx.translate(x,y);ctx.scale(z,z);R(-7,-4,16,15,'#b98d70');R(-9,-6,20,4,'#d3aa82');R(-1,-40,3,35,'#558878');for(const [xx,yy,ww,hh]of [[-17,-37,16,8],[2,-44,15,8],[-13,-25,13,7],[3,-29,15,7],[-8,-50,10,9]]){R(xx,yy,ww,hh,'#5d9d86');R(xx,yy,ww,2,'#80b199');}ctx.restore();}
function shelf(x,y){R(x,y,53,77,'#3a424c');R(x+3,y+3,47,69,'#1e2e3b');for(let row=0;row<2;row++){R(x+2,y+34+row*34,49,4,'#8e7b65');for(let j=0;j<5;j++){let h=17+(j*7)%9;R(x+6+j*8,y+34+row*34-h,6,h,['#9b7b76','#b7a78b','#668f93','#8b97a6','#b39268'][j]);R(x+7+j*8,y+39+row*34-h,4,2,'#d5c5a1');}}plant(x+26,y-5);}
function crownShape(x,y){R(x-10,y,20,6,'#efc66a');R(x-10,y-7,4,9,'#efc66a');R(x-2,y-10,4,11,'#ffe1a0');R(x+6,y-7,4,9,'#efc66a');R(x-8,y+6,16,2,'#b3884f');R(x-1,y+1,3,3,'#6fbeb0');}
function person(x,y,a,t,walking=false,small=false){
  const p=a.personaje||{},q=a.energia?.efectiva??a.energia?.semanal,tired=q!=null&&q<20,sleep=q!=null&&q<10&&!walking;let speed=p.velocidad||1;if(tired)speed*=.35;
  const phase=t*speed,step=Math.sin(phase/110),bob=walking?Math.round(step*2):Math.round(Math.sin(phase/500));
  ctx.save();ctx.translate(x,y+bob);if(small)ctx.scale(.55,.55);
  if(sleep){ctx.translate(6,24);ctx.rotate(.38);}
  const c=p.color||colors[a.id]||'#8e9cb4',skin='#e3b795',hair=p.accesorio==='canas'?'#c2c4c0':a.id==='claude'?'#9e533e':a.id==='agy'?'#223247':'#2e4d40';
  const shoeCol=(p.ropa==='deportiva'||p.ropa==='ligera')?'#eee4cc':'#182530';
  R(-11,4,9,20+(walking?step*3:0),'#273745');R(3,4,9,20-(walking?step*3:0),'#273745');R(-14,23+(walking?step*3:0),13,4,shoeCol);R(3,23-(walking?step*3:0),14,4,shoeCol);
  if(p.ropa==='capa'){R(-21,-28,42,42,'#715980');R(-25,-12,5,27,'#846590');}
  R(-17,-28,34,36,c);R(-20,-23,5,23,c);R(16,-23,6,23,c);R(-3,-29,6,8,skin);
  if(p.ropa==='ligera'){R(-11,-27,22,23,c);R(-6,-27,12,6,'#d6eae2');R(-19,-14,4,13,skin);R(15,-14,4,13,skin);}
  if(/mono/.test(p.ropa)){R(-11,-28,4,29,'#a2c7c1');R(7,-28,4,29,'#a2c7c1');R(-8,-9,17,9,'#396574');R(-6,-7,12,2,'#84afad');if(p.ropa==='mono-gastado')R(7,9,7,6,'#9d886b');}
  if(['traje','prestado','clasica','chaleco'].includes(p.ropa)){R(-5,-27,11,23,'#ddd9c9');R(-1,-25,3,17,p.ropa==='prestado'?'#cb914f':'#526b79');R(-15,-24,6,4,'#c1ac95');}
  if(p.ropa==='tecnica'){R(7,-26,4,30,'#e5914d');R(-13,-16,9,5,'#263e53');R(9,-11,4,2,'#ffd08b');}
  if(p.ropa==='bata'){R(-3,-26,7,34,'#9fbcb6');R(8,-11,7,8,'#baccc4');R(10,-16,2,7,'#71adbf');}
  if(p.ropa==='deportiva'){R(-14,-26,3,31,'#c7e6d9');R(12,-26,3,31,'#c7e6d9');R(-5,-25,10,3,'#315f68');}
  if(p.ropa==='sudadera'){R(-9,-30,18,5,'#e3a786');R(-3,-21,2,13,'#e9d6ad');R(3,-21,2,13,'#e9d6ad');}
  if(p.accesorio==='bolsillos'){R(-13,-18,6,7,'#2c4f5b');R(7,-18,6,7,'#2c4f5b');R(-12,-16,4,2,'#a2c7c1');R(8,-16,4,2,'#a2c7c1');}
  R(-12,-53,25,25,skin);R(-14,-53,28,8,hair);R(-14,-47,5,12,hair);R(10,-48,5,8,hair);R(-11,-57,21,5,hair);R(-15,-39,4,6,skin);R(13,-39,4,6,skin);
  if(p.accesorio==='capucha'){R(-14,-48,28,4,c);R(-15,-46,4,13,c);R(11,-46,4,13,c);}
  if(a.id==='claude')R(-14,-45,3,4,'#e07a5f');
  if(a.id==='agy')R(11,-45,3,4,'#38bdf8');
  if(a.id==='codex')R(-14,-45,3,4,'#10b981');
  const modStr=String(a.modelo||p.personalidad||'').toLowerCase();
  if(/opus|astra|argon/i.test(modStr)){
    R(-2,-64,4,4,'#fbbf24');R(-1,-65,2,6,'#fef08a');R(-3,-63,6,2,'#fef08a');
  }else if(/haiku|luna|flash/i.test(modStr)){
    R(0,-65,2,3,'#38bdf8');R(-2,-63,4,2,'#38bdf8');R(-1,-61,2,2,'#38bdf8');
  }else if(/sonnet|sol/i.test(modStr)){
    R(-2,-64,5,5,'#fb923c');R(-1,-63,3,3,'#1e293b');
  }else if(/fable/i.test(modStr)){
    R(-1,-65,3,6,'#c084fc');
  }
  const blink=Math.floor(phase/180)%23===0;R(-7,-41,3,blink||sleep?1:3,'#293039');R(5,-41,3,blink||sleep?1:3,'#293039');R(-1,-33,5,2,'#a86d60');
  if(p.accesorio==='gafas'){R(-10,-43,11,7,'#2a3443');R(3,-43,10,7,'#2a3443');R(-8,-42,7,3,'#b1cad0');R(5,-42,6,3,'#b1cad0');R(0,-42,4,2,'#2a3443');}
  if(tired){R(-8,-36,5,2,'#947c79');R(4,-36,6,2,'#947c79');}
  if(a.id==='codex'&&p.accesorio==='esfuerzo'&&a.esfuerzo==='medium'){R(-16,-48,4,18,'#172b3a');R(13,-48,4,18,'#172b3a');R(-13,-58,26,4,'#e3a15c');}
  let hands=a.estado==='escribiendo'?Math.round(Math.sin(phase/85)*3):0;
  R(-22,-5+hands,9,7,skin);R(15,-5-hands,9,7,skin);
  if(a.estado==='esperando'||(p.accesorio==='esfuerzo'&&a.esfuerzo==='low')){R(15,-13,10,9,'#e8dfc4');R(24,-11,4,5,'#e8dfc4');}
  if(a.estado==='pensando')text('???',2,-68,11,'#f3d9a1','center');
  if(sleep)text('z Z z',19,-60,12,'#b9ccdf');
  if(p.ropa==='bata'&&tired&&!sleep&&Math.floor(phase/1200)%3===0)text('aaah…',0,-66,9,'#b9ccdf','center');
  if(a.estado==='leyendo'){R(-18,-5,36,18,'#e8e0cc');R(-1,-4,2,16,'#ab9d84');R(4,-1,10,1,'#a49e8e');R(4,4,10,1,'#a49e8e');R(-16+Math.floor(phase/240)%10,-5,2,17,'#fff3d5');}
  if(p.accesorio==='pluma'){R(22,-26,2,24,'#e8d4ae');R(23,-29,5,12,'#e4ceb1');}
  ctx.restore();
  if(sleep)text('z Z z',x-31,y-57,10,'#d0d9e5');
}
function pet(x,y,id,t){ctx.save();ctx.translate(x,y);let b=Math.round(Math.sin(t/700));
  if(id==='claude'){R(-12,-14+b,23,17,'#caa285');R(-13,-24+b,19,15,'#d8b496');R(-13,-29+b,5,8,'#d8b496');R(1,-29+b,5,8,'#d8b496');R(-9,-20+b,3,3,'#365452');R(0,-20+b,3,3,'#365452');R(10,-12,13,4,'#caa285');R(20,-20+b,4,10,'#caa285');}
  if(id==='codex'){R(-12,-24+b,24,27,'#9b8573');R(-10,-28+b,6,6,'#a89580');R(5,-28+b,6,6,'#a89580');R(-10,-21+b,9,11,'#ddd0a7');R(2,-21+b,9,11,'#ddd0a7');R(-7,-18+b,4,4,'#223c43');R(4,-18+b,4,4,'#223c43');R(-1,-10+b,4,5,'#e3b877');R(-14,-12+b,4,12,'#7e6b5e');R(11,-12+b,4,12,'#7e6b5e');}
  if(id==='agy'){R(-16,-13+b,28,16,'#b99471');R(-14,-26+b,23,19,'#d1ad86');R(-18,-26+b,6,19,'#796454');R(8,-26+b,5,18,'#796454');R(-10,-20+b,3,3,'#29313b');R(1,-20+b,3,3,'#29313b');R(-4,-13+b,5,3,'#3b3c3f');R(-1,-8+b,3,5,'#de9e92');R(12,-8,10,4,'#b99471');R(20,-16+(Math.round(Math.sin(t/120))*3),4,11,'#b99471');}
  R(-10,3,7,3,'#7e6856');R(4,3,7,3,'#7e6856');ctx.restore();
}
function city(t){
  const h=new Date().getHours()+new Date().getMinutes()/60;let phase=h<5||h>=19?'Noche':h<7?'Amanecer':h<17?'Día':'Atardecer';
  const skies={Noche:['#17263e','#3c5365'],Amanecer:['#77758c','#d1a288'],Día:['#75a2b4','#b1c8c7'],Atardecer:['#776884','#d9a07f']};
  const gradient=ctx.createLinearGradient(0,44,0,205);gradient.addColorStop(0,skies[phase][0]);gradient.addColorStop(1,skies[phase][1]);ctx.fillStyle=gradient;ctx.fillRect(0,44,1440,159);
  if(phase==='Noche'){for(let i=0;i<65;i++){let x=(i*173+71)%1440,y=53+(i*37)%95;R(x,y,1+(i%3===0),1+(i%3===0),i%4?'#a9b8c8':'#e3d7b5');}R(1266,65,19,19,'#e2dbc2');R(1262,61,16,18,skies[phase][0]);}else{R(1250,70,23,23,'#f5d6a0');for(let j=0;j<6;j++){let x=(j*243+t/500)%1600-80;R(x,73+(j%3)*19,75,5,'#c7ced1');}}
  for(let layer=0;layer<2;layer++)for(let i=0;i<40;i++){let x=i*42+(layer?18:0),height=25+(i*19+layer*7)%64,y=205-height;R(x,y,35,height,layer?'#233a4b':'#3b5163');if(phase==='Noche'||phase==='Atardecer')for(let u=0;u<4;u++)for(let v=0;v<6;v++)if((u+v+i)%3)R(x+5+u*7,y+7+v*9,2,3,(i+v)%3?'#d4b686':'#7699a3');}
  for(let i=0;i<3;i++){let x=i*480;R(x+13,44,7,164,'#152634');R(x+459,44,8,164,'#152634');R(x+20,44,439,5,'#68808a');R(x+20,199,439,8,'#172d3c');R(x+237,49,6,150,'#2b4150');R(x+20,126,439,4,'#2b4150');R(x+23,52,3,144,'#6c8995');R(x+245,55,205,2,'#8fa4a9');}
  return phase;
}
function room(a,i,t,now){
  const x=i*480,cx=x+246,q=a.energia?.efectiva??a.energia?.semanal,p=a.personaje||{},on=!["apagado","descansando"].includes(a.estado)&&!a.enReunion,inTransit=!paused&&travel.some(v=>v.from===a.id&&now>=v.start&&now<v.start+6500);
  R(x+16,212,447,164,'#263a43');R(x+23,219,433,151,i===1?'#314850':'#34454b');
  for(let yy=224;yy<369;yy+=9)for(let xx=x+28;xx<x+450;xx+=12)R(xx,yy,3,1,'#40545b');
  R(x+17,211,446,3,'#849087');R(x+17,374,446,3,'#8b8b75');
  shelf(x+32,214);plant(x+428,279,true);
  R(x+387,304,52,35,'#b4a080');R(x+383,301,60,5,'#d2be98');R(x+389,341,3,14,'#625a50');R(x+434,341,3,14,'#625a50');
  if(a.id==='codex'&&p.accesorio==='esfuerzo'&&a.esfuerzo==='high'){R(x+366,223,60,49,'#c3c9b6');R(x+370,226,52,41,'#324a4c');text('Σ f(x)',x+376,239,10,'#e4debd');text('O(n log n)',x+371,253,7,'#cbd8bd');R(x+374,271,3,25,'#a2a389');R(x+416,271,3,25,'#a2a389');}
  R(cx-35,235,62,57,'#1a2937');R(cx-30,231,52,14,'#263e4d');R(cx-31,289,56,9,'#1b2a35');R(cx-8,293,7,25,'#647581');R(cx-30,316,53,4,'#52636f');
  if(on&&!inTransit&&!a.pose)person(cx-6,281,a,t);
  else if(!on&&a.enReunion){R(cx-22,242,35,37,p.color||'#74818b');R(cx-27,245,7,25,p.color||'#74818b');R(cx+12,244,7,25,p.color||'#74818b');}
  R(cx-117,289,240,20,'#1c2c36');R(cx-109,307,13,41,'#4c423b');R(cx+99,307,13,41,'#4c423b');R(cx-123,280,250,13,'#a48b6c');R(cx-119,280,244,3,'#d0b18a');R(cx-118,293,240,29,'#735e4c');R(cx-113,298,230,2,'#8c755b');
  if(!on&&typeof cartelMesa==='function')cartelMesa(cx-12,246,a.enReunion?(a.fuera||'EN REUNIÓN'):a.estado==='descansando'&&a.vuelve?'VUELVO '+horaCorta(a.vuelve):'VUELVO PRONTO',90,9);
  R(cx+34,228,75,47,'#182735');R(cx+38,232,67,38,on?'#244756':'#1b2d38');R(cx+67,275,7,5,'#263d49');R(cx+55,279,31,3,'#2a414e');
  if(on)for(let n=0;n<5;n++){const advance=a.estado==='escribiendo'?Math.floor(t/180):0;R(cx+43,238+n*6,10+(n*13+advance*4)%46,2,n%2?'#95c8b3':'#83adc2');}
  R(cx+3,283,47,6,'#354b58');for(let k=0;k<10;k++)R(cx+5+k*4,284,2,1,'#91a3a7');
  R(cx-98,278,26,4,'#e0d4b7');R(cx-96,274,24,3,'#f4e6c9');R(cx-90,266,1,7,'#c29e6e');R(cx-62,269,12,12,'#d4c5a9');R(cx-50,271,5,7,'#d4c5a9');R(cx-60,268,8,3,'#69544a');
  const recList=(typeof data!=='undefined'&&data?.reclamos)?(Array.isArray(data.reclamos)?data.reclamos:[data.reclamos]):[];
  const rec=recList.find(r=>r.agente===a.id||(r.agente&&r.agente.startsWith(a.id)));
  if(rec){
    R(cx-114,272,44,15,'#fef08a');R(cx-113,273,42,13,'#fef9c3');
    text('EN RECLAMO',cx-92,278,5,'#854d0e','center');
    text(clipped(rec.tarea,11),cx-92,284,4.5,'#713f12','center');
  }
  const modIcon=/opus|astra|argon/i.test(a.modelo)?'◈ ':/haiku|luna|flash/i.test(a.modelo)?'⚡ ':/sonnet|sol/i.test(a.modelo)?'⚙ ':/fable/i.test(a.modelo)?'✦ ':'• ';
  R(cx-77,302,160,27,'#3e3934');R(cx-75,301,156,25,'#b99b64');R(cx-72,303,150,21,'#ddbf83');text('AGENTE ESTRELLA · '+a.nombre.toUpperCase(),cx+3,312,8,'#3b3d3e','center');text(clipped(modIcon+(a.modelo||'Sin modelo'),27),cx+3,321,7,'#4b4e4c','center');
  if(!crown&&norm(activeThread()?.lider)===a.id)crownShape(cx+91,311);
  fitText(p.personalidad||'Despacho disponible',x+94,222,108,9,colors[a.id],'left');
  // Quota is the only energy source; an unknown quota remains unknown.
  const ew=p.ropa==='deportiva'?120:90;R(cx-ew/2,344,ew,5,'#1c2b35');if(q!=null)R(cx-ew/2,344,ew*Math.max(0,q)/100,5,q<20?'#c5837c':colors[a.id]);
  // La 5 h, aparte: una pila pequeña junto a la barra semanal.
  const c5=a.energia?.cinco_h,bx=cx+ew/2+8;R(bx,341,18,10,'#94a3b8');R(bx+18,344,2,4,'#94a3b8');R(bx+1,342,16,8,'#0f172a');
  if(c5!=null)R(bx+2,343,14*Math.max(0,Math.min(100,c5))/100,6,c5<=0.5?'#ef4444':c5<25?'#f59e0b':'#4ade80');text('5h',bx+24,350,7,'#94a3b8');
  const etq=q==null?'ENERGÍA SIN DATO':`ENERGÍA SEMANAL ${number(q,1)}%`;
  fitText(a.estado==='descansando'&&a.vuelve?etq+' · 5 h agotada, vuelve '+horaCorta(a.vuelve):etq,cx,358,300,7,'#c2d0ce','center');
  pet(x+72,344,a.id,t);
  for(let n=0;n<(a.pasantes||0);n++)person(x+344+(n%2)*33,294+Math.floor(n/2)*48,{...a,estado:'escribiendo',personaje:a.personajesPasantes?.[n]||p,energia:{semanal:100}},t+n*180,false,true);
  if(a.pose&&!a.pose.oculto&&typeof dibujarPose==='function')dibujarPose(a,a.pose,t,1,[x+18,214,x+462]);
  const alarm=(a.alertas||[]).length>0;
  let action=a.estado==='descansando'?'Descansando: 5 h agotada'+(a.vuelve?' · vuelve a las '+horaCorta(a.vuelve):''):a.ultima?`${a.ultima.herramienta}${a.ultima.archivo?' · '+leaf(a.ultima.archivo):''}`:(on?(p.frase||'Listo para trabajar.'):'Guardando el despacho.');
  if(alarm)action='Vigía: '+a.alertas.length+' alerta(s) alta(s) sin revisar';
  R(x+35,385,410,28,alarm?'#59313c':'#1a2b37');R(x+50,381,7,7,alarm?'#59313c':'#1a2b37');text(clipped(action,58),x+51,403,10,alarm?'#ffd0c8':'#c8d7dc');
  if(alarm){R(x+406,286,23,6,'#4b535b');R(x+409,274,17,12,'#d35d65');R(x+412+Math.sin(t/150)*5,276,5,7,'#ffb8a5');if(!paused){ctx.globalAlpha=.08+Math.abs(Math.sin(t/180))*.09;R(x+389,262,55,35,'#f28072');ctx.globalAlpha=1;}}
  if(flashes[a.id]&&now-flashes[a.id]<1200&&!paused){ctx.globalAlpha=(1-(now-flashes[a.id])/1200)*.5;R(cx-40,220,80,70,'#fff4c2');ctx.globalAlpha=1;}
}

// Catálogo de tipos de decoración con pixel art de alto detalle (v3)
function drawDecoracion(tipo, x, y, t) {
  ctx.save();
  const tipoNorm = String(tipo || '').toLowerCase();
  
  if (tipoNorm === 'estatuilla_dorada') {
    // Pedestal de caoba
    R(x - 9, y + 8, 18, 5, '#3b2014');
    R(x - 7, y + 6, 14, 2, '#5d3520');
    // Fuste dorado
    R(x - 3, y, 6, 6, '#b48c36');
    R(x - 1, y, 2, 6, '#fef08a');
    // Estrella / Trofeo dorado
    R(x - 6, y - 9, 12, 9, '#eab308');
    R(x - 4, y - 12, 8, 13, '#facc15');
    R(x - 2, y - 15, 4, 16, '#fef08a');
    // Destello de brillo
    if (Math.floor(t / 400) % 4 === 0) {
      R(x + 2, y - 13, 3, 3, '#ffffff');
    }
  } else if (tipoNorm === 'cuadro_sol_antropico' || tipoNorm === 'cuadro') {
    // Marco de madera noble
    R(x - 17, y - 15, 34, 30, '#5a3821');
    R(x - 15, y - 13, 30, 26, '#1a1815');
    // Lienzo con sol geométrico cálido
    R(x - 13, y - 11, 26, 22, '#2d1512');
    R(x - 5, y - 7, 10, 10, '#ea580c');
    R(x - 3, y - 5, 6, 6, '#fde047');
    // Dunas terracota
    R(x - 13, y + 2, 26, 9, '#991b1b');
    R(x - 9, y + 4, 22, 7, '#b91c1c');
    R(x - 13, y + 9, 26, 2, '#7f1d1d');
  } else if (tipoNorm === 'planta_extra') {
    // Maceta cerámica esmaltada
    R(x - 9, y + 2, 18, 13, '#0284c7');
    R(x - 10, y, 20, 3, '#38bdf8');
    R(x - 8, y + 2, 16, 2, '#451a03'); // tierra fértil
    // Hojas monstera / ficus pixel
    R(x - 2, y - 16, 4, 16, '#15803d');
    R(x - 14, y - 14, 13, 7, '#22c55e');
    R(x + 1, y - 17, 14, 7, '#22c55e');
    R(x - 11, y - 9, 10, 6, '#16a34a');
    R(x + 3, y - 11, 10, 6, '#16a34a');
    // Brillos de hoja
    R(x - 12, y - 14, 8, 2, '#86efac');
    R(x + 3, y - 17, 9, 2, '#86efac');
  } else if (tipoNorm === 'poster_pixel') {
    // Lámina de plano o arquitectura
    R(x - 16, y - 16, 32, 32, '#1e3a8a');
    R(x - 15, y - 15, 30, 30, '#172554');
    // Cuadrícula y esquemas de circuito
    R(x - 13, y - 8, 26, 1, '#3b82f6');
    R(x - 13, y + 2, 26, 1, '#3b82f6');
    R(x - 8, y - 12, 16, 2, '#60a5fa');
    R(x, y - 12, 2, 20, '#60a5fa');
    R(x - 4, y - 2, 8, 8, '#93c5fd');
    // Chinchetas rojas en las esquinas
    R(x - 14, y - 14, 2, 2, '#ef4444');
    R(x + 12, y - 14, 2, 2, '#ef4444');
  } else if (tipoNorm === 'globo_terraqueo') {
    // Base y arco de latón
    R(x - 8, y + 12, 16, 4, '#522b16');
    R(x - 2, y + 7, 4, 6, '#ca8a04');
    R(x - 13, y - 10, 3, 19, '#eab308');
    R(x - 11, y + 7, 10, 3, '#eab308');
    // Esfera azul océano
    R(x - 10, y - 9, 19, 19, '#0284c7');
    // Continentes verdes
    R(x - 7, y - 6, 7, 6, '#15803d');
    R(x + 1, y - 4, 6, 8, '#16a34a');
    R(x - 5, y + 2, 8, 5, '#15803d');
    // Ecuador dorado
    R(x - 9, y, 17, 1, '#fde047');
  } else if (tipoNorm === 'reloj_cucu') {
    // Casita de madera del cuco
    R(x - 12, y - 14, 24, 26, '#451a03');
    R(x - 15, y - 17, 30, 4, '#78350f');
    // Esfera del reloj
    R(x - 6, y - 7, 12, 12, '#fef08a');
    R(x - 1, y - 4, 2, 5, '#1e293b');
    R(x - 3, y - 2, 4, 2, '#1e293b');
    // Cadenas y piñas
    R(x - 6, y + 12, 1, 10, '#d97706');
    R(x + 5, y + 12, 1, 12, '#d97706');
    R(x - 8, y + 21, 5, 6, '#78350f');
    R(x + 3, y + 23, 5, 6, '#78350f');
    // Péndulo oscilante
    const pend = Math.sin(t / 240) * 4;
    R(x - 1 + pend, y + 12, 2, 9, '#ca8a04');
    R(x - 3 + pend, y + 20, 6, 5, '#eab308');
  } else if (tipoNorm === 'taza_campeon') {
    // Taza dorada de campeón
    R(x - 9, y - 4, 18, 16, '#ca8a04');
    R(x - 7, y - 2, 14, 13, '#facc15');
    // Asa
    R(x + 8, y - 1, 5, 10, '#ca8a04');
    R(x + 9, y + 1, 3, 6, '#182433');
    // Emblema #1
    R(x - 2, y + 1, 4, 6, '#451a03');
    // Vapor de café caliente
    if (!paused) {
      const st = Math.sin(t / 200) * 3;
      R(x - 3 + st, y - 9, 2, 4, 'rgba(255,255,255,0.4)');
      R(x + 2 - st, y - 11, 2, 4, 'rgba(255,255,255,0.3)');
    }
  } else if (tipoNorm === 'diploma_enmarcado') {
    // Marco elegante y pergamino
    R(x - 16, y - 14, 32, 28, '#0f172a');
    R(x - 14, y - 12, 28, 24, '#fef3c7');
    // Líneas simuladas de caligrafía
    R(x - 10, y - 8, 20, 2, '#92400e');
    R(x - 8, y - 4, 16, 2, '#b45309');
    R(x - 11, y, 22, 2, '#b45309');
    // Sello de cera lacrada roja con cintas
    R(x - 3, y + 4, 6, 6, '#dc2626');
    R(x - 4, y + 9, 3, 3, '#dc2626');
    R(x + 1, y + 9, 3, 3, '#dc2626');
  } else if (tipoNorm === 'cristal_argon') {
    // Racimo de cristales de argón luminosos
    const glow = 0.65 + Math.sin(t / 320) * 0.35;
    R(x - 10, y + 5, 20, 8, '#334155'); // roca base
    R(x - 7, y - 14, 6, 19, '#06b6d4');
    R(x - 1, y - 19, 7, 24, '#22d3ee');
    R(x + 4, y - 11, 5, 16, '#0891b2');
    R(x + 1, y - 17, 3, 10, '#cffafe'); // arista brillante
    // Halo sutil de luz
    ctx.save();
    ctx.globalAlpha = glow * 0.28;
    R(x - 12, y - 22, 24, 29, '#22d3ee');
    ctx.restore();
  } else if (tipoNorm === 'pila_disquetes') {
    // Pila de 3 disquetes retro de 3.5 pulgadas
    R(x - 12, y + 6, 24, 6, '#1d4ed8');
    R(x - 8, y + 7, 16, 3, '#f8fafc');
    R(x - 13, y + 1, 24, 5, '#1e293b');
    R(x - 9, y + 2, 16, 3, '#ef4444');
    R(x - 11, y - 4, 23, 5, '#64748b');
    R(x - 7, y - 3, 15, 3, '#fef08a');
    // Obturador metálico superior
    R(x + 5, y - 4, 6, 4, '#cbd5e1');
  } else if (tipoNorm === 'ajedrez_estrategico' || tipoNorm === 'ajedrez') {
    // Tablero de ajedrez isométrico con piezas
    R(x - 13, y - 10, 26, 22, '#451a03'); // marco de nogal
    R(x - 11, y - 8, 22, 18, '#fef3c7'); // casillas claras
    // Patrón escaques
    for (let r = 0; r < 4; r++) {
      for (let c = 0; c < 4; c++) {
        if ((r + c) % 2 === 1) R(x - 11 + c * 5.5, y - 8 + r * 4.5, 5.5, 4.5, '#78350f');
      }
    }
    // Rey blanco y caballo negro en píxeles
    R(x - 4, y - 5, 3, 6, '#ffffff'); // rey
    R(x - 5, y - 6, 5, 1, '#ffffff');
    R(x + 2, y - 3, 4, 5, '#171717'); // caballo
  } else if (tipoNorm === 'estrella_dorada' || tipoNorm === 'estrella') {
    // Estrella dorada con resplandor sobre pedestal
    R(x - 8, y + 7, 16, 5, '#78350f'); // base caoba
    R(x - 2, y + 2, 4, 6, '#ca8a04'); // pedestal
    // Estrella 8-puntas
    R(x - 8, y - 8, 16, 10, '#facc15');
    R(x - 5, y - 11, 10, 16, '#facc15');
    R(x - 2, y - 13, 4, 20, '#fde047');
    R(x - 10, y - 5, 20, 4, '#fde047');
    R(x - 1, y - 3, 2, 2, '#ffffff'); // brillo central
  } else if (tipoNorm === 'escudo_auditoria' || tipoNorm === 'escudo') {
    // Escudo de seguridad y auditoría en acero azulado
    R(x - 10, y - 12, 20, 14, '#1e293b');
    R(x - 8, y + 2, 16, 8, '#1e293b');
    R(x - 5, y + 10, 10, 5, '#1e293b');
    R(x - 2, y + 15, 4, 3, '#1e293b');
    // Borde cian cibernético y check de auditoría
    R(x - 8, y - 10, 16, 11, '#0f172a');
    R(x - 6, y + 1, 12, 7, '#0f172a');
    R(x - 4, y - 3, 2, 4, '#38bdf8'); // checkmark
    R(x - 2, y + 1, 2, 3, '#38bdf8');
    R(x, y - 1, 2, 3, '#38bdf8');
    R(x + 2, y - 4, 2, 4, '#38bdf8');
  } else {
    // Fallback decorativo: placa conmemorativa con estrella
    R(x - 12, y - 10, 24, 20, '#5a3d28');
    R(x - 10, y - 8, 20, 16, '#caa460');
    R(x - 8, y - 6, 16, 12, '#fef08a');
    R(x - 3, y - 3, 6, 6, '#b45309');
  }

  ctx.restore();
}

  return { person, pet, plant, shelf, city, room, crownShape, drawDecoracion };
})();
if (typeof window !== 'undefined') {
  window.drawDecoracion = V1.drawDecoracion;
}
