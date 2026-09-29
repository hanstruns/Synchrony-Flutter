'use strict';
const { randomInt, randomBytes } = require('node:crypto');
const fail = message => { throw new Error(message); };
const int = (v, min, max) => Number.isSafeInteger(v) && v >= min && v <= max;
class Game {
  constructor({ now = Date.now, countdown = 5000, grace = 30000, idle = 900000, maxDeck = 100000 } = {}) {
    Object.assign(this, { now, countdown, grace, idle, maxDeck }); this.rooms = new Map();
  }
  code() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let code; do { code = Array.from({length:6}, () => chars[randomInt(chars.length)]).join(''); } while(this.rooms.has(code));
    return code;
  }
  create({ players, deck, public: online = false }) {
    if (!int(deck, 2, this.maxDeck)) fail(`La baraja debe tener entre 2 y ${this.maxDeck} cartas.`);
    if (!int(players, 1, deck)) fail('Elige al menos un jugador y una carta por jugador.');
    if (online && (!int(players,2,8) || deck !== 100)) fail('La búsqueda online admite de 2 a 8 jugadores y 100 cartas.');
    const room = { code:this.code(), capacity:players, deck, public:online, players:[], phase:'lobby', round:1, lives:5,
      last:0, dealt:0, played:0, removed:0, revision:0, eventId:0, event:{type:'welcome',text:'La conexión empieza aquí.'}, lastActivity:this.now(), deadline:null, countdownAt:null };
    this.rooms.set(room.code, room); return room;
  }
  emit(r, type, text, extra={}) { r.revision++; r.event = {type,text,id:++r.eventId,...extra}; }
  touch(r) { r.lastActivity = this.now(); }
  join(r, name) {
    if(r.phase !== 'lobby') fail('La partida ya ha empezado.');
    if(r.players.length >= r.capacity) fail('La sala está completa.');
    if(typeof name !== 'string' || !name.trim() || name.trim().length>24) fail('Escribe un nombre de 1 a 24 caracteres.');
    const p = { id:randomBytes(12).toString('hex'), token:randomBytes(32).toString('hex'), name:name.trim(), hand:[], ready:false,
      online:true, lastSeen:this.now(), disconnectedAt:null, excluded:false };
    r.players.push(p); this.touch(r); this.emit(r,'join',`${p.name} se ha conectado.`); return p;
  }
  active(r) { return r.players.filter(p=>!p.excluded); }
  alive(r) { return this.active(r).filter(p=>p.online); }
  ready(r,p) {
    if(!['lobby','between','retry'].includes(r.phase) || p.excluded) fail('Ahora no puedes marcarte como listo.');
    p.ready = !p.ready; this.touch(r); this.emit(r,'ready',p.ready ? `${p.name} está listo.` : `${p.name} necesita un momento.`); this.maybeCountdown(r);
  }
  maybeCountdown(r) {
    const active=this.active(r);
    if(!['lobby','between','retry'].includes(r.phase) || !active.length) return;
    if(r.phase==='lobby' && active.length!==r.capacity) return;
    if(active.every(p=>p.online && p.ready)) {
      r.returnPhase=r.phase; r.phase='countdown'; r.countdownAt=this.now()+this.countdown;
      this.emit(r,'countdown','Respirad. Empezamos juntos.');
    }
  }
  cancelCountdown(r) {
    if(r.phase!=='countdown') return;
    r.phase=r.returnPhase; r.countdownAt=null;
    r.players.forEach(p=>p.ready=false); this.emit(r,'pause','Cuenta atrás cancelada. Volved a confirmar.');
  }
  start(r) {
    const active=this.active(r); if(!active.length) return;
    r.players.forEach(p=>{p.hand=[];p.ready=false;});
    const deck=Array.from({length:r.deck},(_,i)=>i+1);
    for(let i=deck.length-1;i>0;i--) { const j=randomInt(i+1); [deck[i],deck[j]]=[deck[j],deck[i]]; }
    r.dealt=Math.min(r.deck,active.length*r.round);
    for(let i=0;i<r.dealt;i++) active[i%active.length].hand.push(deck[i]);
    active.forEach(p=>p.hand.sort((a,b)=>a-b));
    r.last=0; r.played=0; r.removed=0; r.phase='playing'; r.countdownAt=null; r.deadline=this.now()+r.deck*5000;
    this.emit(r,'start',`Ronda ${r.round}. Escuchad vuestro ritmo.`);
  }
  lose(r,text) {
    r.lives--; r.phase=r.lives>0?'retry':'lost'; r.deadline=null;
    r.players.forEach(p=>{p.ready=false;p.hand=[];});
    this.emit(r,r.phase==='lost'?'lost':'mistake',text);
  }
  complete(r) {
    if(r.phase!=='playing' || !this.active(r).length || this.active(r).some(p=>p.hand.length)) return;
    // Retirar cartas por desconexión nunca permite alcanzar artificialmente el 79 %.
    const victory=r.played>=Math.ceil(r.deck*.79);
    r.phase=victory?'won':'between'; r.deadline=null;
    this.emit(r,victory?'won':'success',victory?'Vuestras mentes están enlazadas.':`Ronda ${r.round} superada.`);
    if(!victory) r.round++;
    r.players.forEach(p=>p.ready=false);
  }
  play(r,p,card,revision) {
    if(r.phase!=='playing' || p.excluded || !p.online) fail('No puedes jugar en este momento.');
    if(revision!==r.revision) fail('La mesa ha cambiado. Comprueba tu carta y vuelve a pulsar.');
    if(!Number.isSafeInteger(card) || !p.hand.includes(card)) fail('Esa carta no está en tu mano.');
    if(this.now()>=r.deadline) { this.lose(r,'Se agotó el tiempo.'); return; }
    this.touch(r);
    const lowest=this.active(r).reduce((min,x)=>x.hand.length?Math.min(min,x.hand[0]):min,Infinity);
    if(card!==lowest) { this.lose(r,`${p.name} jugó ${card}, pero quedaba una carta menor (${lowest}).`); return; }
    p.hand.splice(p.hand.indexOf(card),1); r.last=card; r.played++;
    this.emit(r,'card',`${p.name} ha jugado ${card}.`,{card,player:p.name}); this.complete(r);
  }
  connect(r,p) {
    p.lastSeen=this.now();
    if(!p.online) {p.online=true;p.disconnectedAt=null;this.emit(r,'reconnect',`${p.name} ha vuelto${p.excluded?' como espectador':''}.`);}
  }
  disconnect(r,p) {
    if(!p.online) return;
    p.online=false;p.ready=false;p.disconnectedAt=this.now();this.cancelCountdown(r);
    this.emit(r,'disconnect',`${p.name} perdió la conexión. Tiene 30 segundos para volver.`);
  }
  remove(r,p) {
    this.cancelCountdown(r);
    if(r.phase==='lobby') r.players=r.players.filter(x=>x!==p);
    else { r.removed+=p.hand.length; p.hand=[]; p.excluded=true;p.ready=false; }
    this.emit(r,'leave',`${p.name} ya no participa. Sus cartas se retiran.`);
    this.complete(r); this.maybeCountdown(r);
    if(!this.active(r).length) {r.phase='abandoned';r.deadline=null;this.emit(r,'abandoned','La partida se ha quedado sin jugadores.');}
  }
  tick() {
    for(const [code,r] of this.rooms) {
      if(this.now()-r.lastActivity>=this.idle) {this.rooms.delete(code);continue;}
      for(const p of [...r.players]) {
        if(p.online && this.now()-p.lastSeen>=15000) this.disconnect(r,p);
        if(!p.online && !p.excluded && p.disconnectedAt!==null && this.now()-p.disconnectedAt>=this.grace) this.remove(r,p);
      }
      if(r.phase==='countdown' && this.now()>=r.countdownAt) this.start(r);
      if(r.phase==='playing' && this.now()>=r.deadline) this.lose(r,'Se agotó el tiempo. Respira y vuelve a intentarlo.');
    }
  }
  view(r,p) {
    return {code:r.code,capacity:r.capacity,deck:r.deck,public:r.public,phase:r.phase,round:r.round,lives:r.lives,last:r.last,
      dealt:r.dealt,played:r.played,removed:r.removed,revision:r.revision,event:r.event,deadline:r.deadline,countdownAt:r.countdownAt,serverNow:this.now(),
      me:p.id,hand:p.hand,players:r.players.map(x=>({id:x.id,name:x.name,ready:x.ready,online:x.online,excluded:x.excluded,count:x.hand.length,disconnectedAt:x.disconnectedAt}))};
  }
}
module.exports={Game};
