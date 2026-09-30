"""Dos composiciones instrumentales originales. Ejecutar con Python + numpy.
Síntesis propia: sin voces, grabaciones ni muestras de terceros.
"""
from pathlib import Path
import numpy as np
import wave
RATE = 24000
ROOT = Path(__file__).resolve().parents[1] / 'assets/music'
ROOT.mkdir(parents=True, exist_ok=True)
def hz(note): return 440 * 2 ** ((note-69)/12)
def compose(name, bpm, seed, chords, airy=False):
    rng = np.random.default_rng(seed)
    beat = 60/bpm
    length = 64*beat
    n = round(length*RATE)
    out = np.zeros((n,2), dtype=np.float64)
    def place(signal, start, pan=0, gain=1):
        ids=(np.arange(len(signal))+round(start*RATE))%n
        left=np.sqrt((1-pan)/2); right=np.sqrt((1+pan)/2)
        np.add.at(out[:,0],ids,signal*gain*left)
        np.add.at(out[:,1],ids,signal*gain*right)
    def tone(note,duration,kind='keys'):
        t=np.arange(round(duration*RATE))/RATE; f=hz(note)
        if kind=='pad':
            attack=np.minimum(t/1.8,1); release=np.minimum((duration-t)/2.2,1)
            return .25*attack*release*(np.sin(2*np.pi*f*t)+.25*np.sin(2*np.pi*(f*1.002)*t)+.12*np.sin(2*np.pi*f*2*t))
        if kind=='bass': return .55*np.minimum(t/.07,1)*np.exp(-t/1.1)*np.minimum((duration-t)/.15,1)*np.sin(2*np.pi*f*t)
        env=(1-np.exp(-t*110))*np.exp(-t/(1.4 if kind=='bell' else .9))*np.minimum((duration-t)/.15,1)
        return .34*env*(np.sin(2*np.pi*f*t+(.6 if kind=='bell' else .3)*np.exp(-t*3)*np.sin(2*np.pi*2*f*t))+.12*np.sin(2*np.pi*3*f*t)*np.exp(-t*3))
    def echo(sig,start,pan,gain):
        place(sig,start,pan,gain)
        for delay,amp in [(beat*.75,.25),(beat*1.5,.12),(beat*2.25,.06)]: place(sig,start+delay,-pan,gain*amp)
    for bar in range(16):
        chord=chords[bar%len(chords)]; start=bar*4*beat
        for i,note in enumerate(chord): place(tone(note,4*beat+2.2,'pad'),start-.8,(i-1.5)/2.6,.12)
        place(tone(chord[0]-24,3.5*beat,'bass'),start,0,.17)
        for i,offset in enumerate([.12,1.65,2.85] if not airy else [.2,2.6]):
            note=chord[(bar+i)%len(chord)]+(12 if i==1 else 0)
            echo(tone(note,3.8),start+offset*beat,(-1 if i%2 else 1)*.3,.20 if not airy else .14)
        if bar%2==0:
            note=chord[(bar//2+2)%4]+12
            echo(tone(note,5,'bell'),start+3.25*beat,-.4,.085)
        # Golpe muy suave y escobilla sintetizados; nunca se usan voces.
        for offset in ([0,2.5] if not airy else [0]):
            t=np.arange(round(.32*RATE))/RATE
            kick=np.sin(2*np.pi*(48*t+2.8*(1-np.exp(-t*18))))*np.exp(-t*18)*np.minimum(t/.007,1)
            place(kick,start+offset*beat,0,.055 if not airy else .026)
        if not airy:
            for offset in [1,3]:
                t=np.arange(round(.16*RATE))/RATE
                noise=rng.normal(0,1,len(t)); noise=np.convolve(noise,np.ones(8)/8,'same')
                place(noise*np.exp(-t*32)*np.minimum(t/.005,1),start+offset*beat,.2,.035)
    # Reverberación circular: también se conserva la cola al repetir el archivo.
    dry=out.copy()
    for delay,amp in [(.137,.10),(.293,.08),(.487,.055),(.811,.035)]:
        out += np.roll(dry,round(delay*RATE),axis=0)[:,::-1]*amp
    # Filtro circular suave sin discontinuidad de estado en el punto de bucle.
    freq=np.fft.rfftfreq(n,1/RATE); filt=1/(1+(freq/5500)**4)
    for ch in range(2): out[:,ch]=np.fft.irfft(np.fft.rfft(out[:,ch])*filt,n=n)
    out -= out.mean(axis=0)
    out=np.tanh(out*1.8)
    out*=.72/max(np.max(np.abs(out)),.001)
    pcm=(out*32767).astype('<i2')
    with wave.open(str(ROOT/f'{name}.wav'),'wb') as w:
        w.setparams((2,2,RATE,0,'NONE','not compressed'));w.writeframes(pcm.tobytes())
    print(name,round(length,2),'s; pico',round(float(np.max(np.abs(out))),3),'rms',round(float(np.sqrt(np.mean(out**2))),3),'salto bucle',np.max(np.abs(out[0]-out[-1])))
compose('menu',66,104,[[57,60,64,67],[53,57,60,64],[60,64,67,71],[55,59,62,69]])
compose('partida',58,205,[[50,57,60,64],[53,57,60,67],[48,55,59,62],[55,57,62,65]],True)
