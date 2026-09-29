const {test,after,before}=require('node:test');
const assert=require('node:assert/strict');
const {server,game}=require('../server');
let base;
before(async()=>{await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base='http://127.0.0.1:'+server.address().port;});
after(()=>server.close());
async function api(body,session){const res=await fetch(base+'/api',{method:'POST',headers:{'Content-Type':'application/json',...(session?{Authorization:'Bearer '+session.token,'X-Room-Code':session.code}:{})},body:JSON.stringify(body)});return {status:res.status,...await res.json()};}
test('HTTP + SSE: dos clientes, privacidad, jugadas, reintento y reconexión',async()=>{
 const a=await api({action:'create',players:2,deck:100,name:'Luna'});const b=await api({action:'join',code:a.code,name:'Leo'});assert.equal(a.status,200);assert.equal(b.status,200);
 const abortA=new AbortController(),abortB=new AbortController();
 async function stream(s,signal){const res=await fetch(base+'/events',{headers:{Authorization:'Bearer '+s.token,'X-Room-Code':s.code},signal});assert.equal(res.status,200);const reader=res.body.getReader();let buffer='';return async()=>{while(true){const at=buffer.indexOf('\n\n');if(at>=0){const frame=buffer.slice(0,at);buffer=buffer.slice(at+2);if(frame.startsWith('data: '))return JSON.parse(frame.slice(6));continue}const part=await reader.read();assert.equal(part.done,false);buffer+=new TextDecoder().decode(part.value)}};}
 const nextA=await stream(a,abortA.signal),nextB=await stream(b,abortB.signal);
 try{await nextA();await nextB();await api({action:'ready'},a);await api({action:'ready'},b);const r=game.rooms.get(a.code);assert.equal(r.phase,'countdown');game.start(r);
 let ar=await api({action:'ping'},a),br=await api({action:'ping'},b);assert.equal(ar.state.hand.length,1);assert.equal(br.state.hand.length,1);assert.ok(ar.state.players.every(p=>p.hand===undefined));
 const players=[{s:a,n:ar.state.hand[0]},{s:b,n:br.state.hand[0]}].sort((x,y)=>x.n-y.n);
 for(const {s,n}of players){const v=await api({action:'ping'},s);const result=await api({action:'play',card:n,revision:v.state.revision},s);assert.equal(result.status,200);}
 assert.equal(r.phase,'between');
 let frame;do{frame=await nextB()}while(frame.phase!=='between');assert.equal(frame.round,2);
 const prior=[...game.rooms.get(a.code).players[0].hand];abortA.abort();await new Promise(resolve=>setTimeout(resolve,50));assert.equal(r.players[0].online,false);
 ar=await api({action:'ping'},a);assert.equal(ar.status,200);assert.deepEqual(ar.state.hand,prior);
 const cheat=await api({action:'play',card:101,revision:r.revision},{code:a.code,token:'wrong'});assert.equal(cheat.status,400);
 }finally{abortA.abort();abortB.abort();}
});
test('matchmaking agrupa por tamaño y no expone salas privadas',async()=>{const a=await api({action:'match',players:3,name:'A'}),b=await api({action:'match',players:3,name:'B'}),c=await api({action:'match',players:4,name:'C'});assert.equal(a.code,b.code);assert.notEqual(a.code,c.code);assert.equal(a.state.deck,100);assert.equal(a.state.public,true);});
test('el servidor solo publica los archivos de interfaz permitidos',async()=>{assert.equal((await fetch(base+'/server.js')).status,404);assert.equal((await fetch(base+'/game.js')).status,404);assert.equal((await fetch(base+'/')).status,200);assert.equal((await fetch(base+'/health')).status,200);});
