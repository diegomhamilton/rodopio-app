"""Create a separate, editable Icon Composer design study; leaves build 10 unchanged."""
from pathlib import Path
import json
base=Path(__file__).resolve().parents[1]
root=base/'assets/branding/Rodopio-fluid-v4.icon'
assets=root/'Assets';assets.mkdir(parents=True,exist_ok=True)
shapes=[
('01-face-azul-superior','#249DF5','M 238 350 C 302 427 647 448 785 341 C 804 326 822 347 809 377 C 750 488 411 499 261 425 C 231 410 211 373 228 352 Q 233 346 238 350 Z'),
('02-face-azul-central','#249DF5','M 244 485 C 333 563 653 586 781 474 C 801 456 820 482 803 520 C 759 628 436 676 274 581 C 241 562 218 514 233 492 Q 238 482 244 485 Z'),
('03-faixa-azul-inferior','#249DF5','M 289 632 C 376 710 624 723 738 614 C 759 594 779 620 758 659 C 700 766 425 792 313 706 C 283 683 267 653 280 637 Q 284 629 289 632 Z'),
('08-triangulo-roxo-ponta','#8853F5','M 452 791 C 484 807 531 811 569 791 Q 577 787 571 800 C 555 826 533 843 521 861 Q 514 872 507 861 C 494 842 468 824 452 805 Q 444 793 452 791 Z'),
('04-verso-roxo-superior','#8853F5','M 246 333 C 300 256 626 246 758 309 C 783 321 793 331 796 344 L 772 359 C 718 306 403 300 286 361 Q 258 367 246 347 Q 242 339 246 333 Z'),
('05-verso-roxo-central','#8853F5','M 252 470 C 355 420 652 423 767 459 Q 784 465 785 475 L 761 497 C 651 470 383 484 280 515 Q 254 505 249 488 Q 246 479 252 470 Z'),
('06-verso-roxo-inferior','#8853F5','M 297 613 C 398 559 632 563 723 600 Q 741 608 739 619 L 713 643 C 622 612 411 632 323 661 Q 298 646 293 630 Q 290 620 297 613 Z'),
('07-fita-coroa','#8853F5','M 497 202 C 535 181 567 211 548 248 C 528 288 451 302 406 311 L 360 298 C 391 273 474 258 492 239 C 506 225 506 213 497 202 Z')]
layers=[]
for name,color,path in shapes:
 filename=name+'.svg'
 # Increase the visible ellipse depth without changing the native layered structure.
 if name.startswith(('01-', '04-')):
  adjustment='translate(512 360) scale(0.90 1.18) translate(-512 -360)'
 elif name.startswith(('02-', '05-')):
  adjustment='translate(512 510) scale(1 1.20) translate(-512 -510)'
 elif name.startswith(('03-', '06-')):
  adjustment='translate(512 650) scale(1 1.20) translate(-512 -650)'
 elif name.startswith('07-'):
  adjustment='translate(512 280) scale(0.90 0.90) translate(-512 -280)'
 else:
  adjustment='translate(0 12)'
 (assets/filename).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><g transform="rotate(-10 512 512)"><g transform="{adjustment}"><path d="{path}" fill="{color}"/></g></g></svg>')
 layers.append({'image-name':filename,'name':name,'glass':True,'hidden':False,'position':{'scale':1,'translation-in-points':[0,0]}})
doc=json.loads((base/'App/Rodopio.icon/icon.json').read_text())
doc['groups'][0]['layers']=layers
for layer in doc['groups'][1]['layers']:
 name=layer['image-name'];(assets/name).write_bytes((base/'App/Rodopio.icon/Assets'/name).read_bytes())
(root/'icon.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
print(root)
