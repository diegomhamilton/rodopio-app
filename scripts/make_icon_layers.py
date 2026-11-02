from pathlib import Path
import json, math
root=Path(__file__).resolve().parents[1]/'App/Rodopio.icon'
assets=root/'Assets'
assets.mkdir(parents=True,exist_ok=True)
for previous in assets.glob('*.svg'):
 previous.unlink()
layers=[]
def svg(name, body):
 (assets/name).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'+body+'</svg>')
def ribbon(t):
 theta=-math.pi/2+5.5*math.pi*t
 r=350*math.sin(math.pi*t)**0.8*(1-0.25*t)
 x=512+r*math.cos(theta)
 y=190+655*t+155*math.sin(theta)*math.sin(math.pi*t)
 width=(56*math.sin(math.pi*t)**0.6)
 return x,y,width
# Alternating front/reverse faces are separate artwork layers, kept on an identical canvas.
# The gaps are transparent geometry, not painted highlights.
bounds=[0]+[(k*math.pi+math.pi/2)/(5.5*math.pi) for k in range(6) if 0<(k*math.pi+math.pi/2)/(5.5*math.pi)<1]+[1]
segments=list(zip(bounds,bounds[1:]))
for i,(a,b) in enumerate(segments):
 a += 0.0015 if a>0 else 0
 b -= 0.0015 if b<1 else 0
 top=[]; bottom=[]
 for j in range(101):
  t=a+(b-a)*j/100
  x,y,w=ribbon(t)
  x0,y0,_=ribbon(max(0,t-0.0001));x1,y1,_=ribbon(min(1,t+0.0001))
  dx=x1-x0;dy=y1-y0;length=math.hypot(dx,dy)
  nx=-dy/length;ny=dx/length
  top.append((x+nx*w/2,y+ny*w/2));bottom.append((x-nx*w/2,y-ny*w/2))
 bottom.reverse()
 path='M '+' L '.join(f'{x:.2f},{y:.2f}' for x,y in top+bottom)+' Z'
 color='#824DFA' if i%2==0 else '#219EFA'
 name=f'{i+1:02d}-fita-'+('verso-roxo' if i%2==0 else 'face-azul')+'.svg'
 svg(name,f'<path d="{path}" fill="{color}"/>')
 layers.append({'image-name':name,'name':f'Volta {i//2+1} · '+('verso roxo' if i%2==0 else 'face azul'),'glass':True})
# Back-facing ribbons first, front-facing surfaces last.
layers=layers[::2]+layers[1::2]
sounds=[('som-superior-externo','M 710 210 C 825 225 882 285 890 350'),('som-superior-interno','M 745 250 C 816 267 849 299 860 335'),('som-inferior-externo','M 166 625 C 168 702 224 749 312 765'),('som-inferior-interno','M 190 662 C 214 711 249 730 300 738')]
soundlayers=[]
for i,(name,path) in enumerate(sounds):
 file=f'{i+10:02d}-{name}.svg';svg(file,f'<path d="{path}" fill="none" stroke="#F8EAB0" stroke-width="9" stroke-linecap="round"/>')
 soundlayers.append({'image-name':file,'name':name,'glass':True})
doc={'fill-specializations':[{'value':{'solid':'srgb:0.025,0.045,0.16,1.00000'}}],'groups':[{'blur-material':0.1,'layers':layers,'lighting':'individual','specular':True,'translucency':{'enabled':True,'value':0.22},'shadow':{'kind':'neutral','opacity':0.35}},{'blur-material':0.1,'layers':soundlayers,'lighting':'individual','specular':True,'translucency':{'enabled':True,'value':0.1},'shadow':{'kind':'neutral','opacity':0.2}}],'supported-platforms':{'squares':'shared','circles':['watchOS']}}
for group in doc['groups']:
 for layer in group['layers']:
  layer.update({'hidden':False,'position':{'scale':1,'translation-in-points':[0,0]}})
(root/'icon.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
print(len(layers), 'faces +',len(soundlayers),'traços sonoros')
