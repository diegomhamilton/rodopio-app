#!/usr/bin/env python3
from pathlib import Path
import re, plistlib, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
source=(root/'Ciranda.xcodeproj/project.pbxproj').read_text()
source=re.sub(r'//[^\n]*','',source)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',source)
pos=0
def parse():
    global pos
    t=tokens[pos];pos+=1
    if t=='{':
        result={}
        while tokens[pos]!='}':
            k=parse();assert tokens[pos]=='=';pos+=1
            result[k]=parse();assert tokens[pos]==';';pos+=1
        pos+=1;return result
    if t=='(':
        result=[]
        while tokens[pos]!=')':
            result.append(parse())
            if tokens[pos]==',':pos+=1
            else:assert tokens[pos]==')'
        pos+=1;return result
    return t[1:-1] if t.startswith('"') else t
project=parse();assert pos==len(tokens)
objects=project['objects'];assert project['rootObject'] in objects
for value in objects.values():
    for key in ['fileRef','mainGroup','productRefGroup','productReference','target','targetProxy','containerPortal','buildConfigurationList','remoteGlobalIDString']:
        if key in value:assert value[key] in objects,(key,value[key])
    for key in ['children','buildConfigurations','buildPhases','dependencies','files','targets']:
        for item in value.get(key,[]):assert item in objects,(key,item)
    if value['isa']=='PBXFileReference' and value.get('sourceTree')=='<group>':
        path=root/value['path']
        assert path.is_dir() if value.get('lastKnownFileType') in ('folder.assetcatalog','folder.iconcomposer.icon') else path.is_file(),value
with (root/'App/Info.plist').open('rb') as f:info=plistlib.load(f)
assert '_ciranda-sixteen._tcp' in info['NSBonjourServices']
ET.parse(root/'Ciranda.xcodeproj/xcshareddata/xcschemes/Ciranda.xcscheme')
assert len([v for v in objects.values() if v['isa']=='PBXNativeTarget'])==2
print('PASS: OpenStep project parsed; all object/file references resolve; Info.plist and shared scheme valid.')
