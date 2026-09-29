'use strict';
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const {Game}=require('./game');
const game=new Game();
const streams=new Map();
const limits=new Map();
const allowed=(process.env.ALLOWED_ORIGINS||'').split(',').map(x=>x.trim()).filter(Boolean);
const port=Number(process.env.PORT)||3000;
function publish() {
  for(const [token,s] of streams) {
    const r=game.rooms.get(s.code);
    const p=r?.players.find(p=>p.token===token);
    if(!r || !p) {s.res.write('event: expired\ndata: {}\n\n');s.res.end();streams.delete(token);continue;}
    if(s.revision!==r.revision) {s.res.write(`data: ${JSON.stringify(game.view(r,p))}\n\n`);s.revision=r.revision;}
  }
}
function auth(req) {
  const token=(req.headers.authorization||'').replace(/^Bearer /,'');
  const code=req.headers['x-room-code'];
  const r=game.rooms.get(code); const p=r?.players.find(p=>p.token===token);
  if(!p) throw Error('No se encuentra tu sesión. La sala puede haber caducado.');
  return {r,p};
}
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml','.webmanifest':'application/manifest+json'};
const publicFiles=new Set(['index.html','styles.css','app.js','config.js','icon.svg','manifest.webmanifest']);
const server=http.createServer(async(req,res)=>{
  const origin=req.headers.origin;
  res.setHeader('X-Content-Type-Options','nosniff');
  if(origin && (!allowed.length || allowed.includes(origin))) {res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
  res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization, X-Room-Code');
  res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');
  const json=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
  if(origin && allowed.length && !allowed.includes(origin)) return json(403,{error:'Origen no autorizado en ALLOWED_ORIGINS.'});
  if(req.method==='OPTIONS') {res.writeHead(204);return res.end();}
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/health') return json(200,{ok:true});
  if(url.pathname==='/events' && req.method==='GET') {
    // Fetch streaming permite enviar el token en una cabecera, nunca en la URL.
    try {
      const {r,p}=auth(req); game.connect(r,p);
      const old=streams.get(p.token);if(old) old.res.end();
      res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache, no-transform','Connection':'keep-alive','X-Accel-Buffering':'no'});
      res.write(`data: ${JSON.stringify(game.view(r,p))}\n\n`);
      const s={res,code:r.code,revision:r.revision};streams.set(p.token,s);
      req.on('close',()=>{if(streams.get(p.token)===s){streams.delete(p.token);game.disconnect(r,p);publish();}});
      publish();return;
    } catch(e) {return json(401,{error:e.message});}
  }
  if(url.pathname==='/api' && req.method==='POST') {
    const ip=req.socket.remoteAddress;let limit=limits.get(ip);
    if(!limit || Date.now()-limit.time>10000) {limit={time:Date.now(),count:0};limits.set(ip,limit);}
    if(++limit.count>1200) return json(429,{error:'Demasiadas peticiones. Espera unos segundos.'});
    try {
      let body='';for await(const chunk of req) {body+=chunk;if(body.length>4096) throw Error('Petición demasiado grande.');}
      const b=JSON.parse(body);let r,p;
      if(['create','join','match'].includes(b.action)) {
        if(typeof b.name!=='string' || !b.name.trim() || b.name.trim().length>24) throw Error('Escribe un nombre de 1 a 24 caracteres.');
        if(b.action==='create') {if(game.rooms.size>=1000) throw Error('Servidor lleno. Prueba más tarde.');r=game.create(b);}
        if(b.action==='join') {r=game.rooms.get(b.code);if(!r) throw Error('No existe esa sala. Respeta las mayúsculas y minúsculas.');}
        if(b.action==='match') {
          if(!Number.isInteger(b.players)||b.players<2||b.players>8) throw Error('Elige entre 2 y 8 jugadores.');
          r=[...game.rooms.values()].find(r=>r.public && r.phase==='lobby' && r.capacity===b.players && r.players.length<r.capacity);
          if(!r) {if(game.rooms.size>=1000) throw Error('Servidor lleno.');r=game.create({players:b.players,deck:100,public:true});}
        }
        p=game.join(r,b.name);publish();return json(200,{token:p.token,code:r.code,state:game.view(r,p)});
      }
      ({r,p}=auth(req));game.connect(r,p);
      if(b.action==='ready') game.ready(r,p);
      else if(b.action==='play') game.play(r,p,b.card,b.revision);
      else if(b.action==='leave') {game.touch(r);game.remove(r,p);const s=streams.get(p.token);streams.delete(p.token);if(s)s.res.end();publish();return json(200,{ok:true});}
      else if(b.action!=='ping') throw Error('Acción desconocida.');
      publish();return json(200,{state:game.view(r,p)});
    }catch(e){return json(400,{error:e.message||'Petición no válida.'});}
  }
  if(req.method==='GET') {
    const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
    if(publicFiles.has(file)) {res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'text/plain'});return fs.createReadStream(path.join(__dirname,file)).pipe(res);}
  }
  json(404,{error:'No encontrado.'});
});
setInterval(()=>{game.tick();publish();for(const [ip,x] of limits)if(Date.now()-x.time>60000)limits.delete(ip);},250).unref();
setInterval(()=>{for(const s of streams.values())s.res.write(': keepalive\n\n');},10000).unref();
if(require.main===module) server.listen(port,'0.0.0.0',()=>console.log(`Synchrony disponible en http://localhost:${port}`));
module.exports={server,game};
