#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; no XcodeGen or CocoaPods required."""
from pathlib import Path
import hashlib, plistlib
root=Path(__file__).resolve().parents[1]
project=root/'Ciranda.xcodeproj'
project.mkdir(exist_ok=True)
objects={}
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name,body):
    i=uid(name);objects[i]=body;return i
def quoted(s):return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
def arr(items):return '('+','.join(items)+',)' if items else '()'
sourcefiles=sorted([*root.glob('App/*.swift'),*root.glob('Core/*.c')])
testfiles=sorted(root.glob('Tests/*.swift'))
refs=[]; build=[]; testbuild=[]
for path in sourcefiles+testfiles+[root/'App/Bridge.h',*root.glob('Core/*.h'),root/'App/Info.plist']:
    relative=str(path.relative_to(root)); typ={'.swift':'sourcecode.swift','.c':'sourcecode.c.c','.h':'sourcecode.c.h','.plist':'text.plist.xml'}[path.suffix]
    ref=add(relative, f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {quoted(relative)}; sourceTree = "<group>";')
    refs.append(ref)
    if path in sourcefiles or path in testfiles:
        b=add('build:'+relative,f'isa = PBXBuildFile; fileRef = {ref};')
        (testbuild if path in testfiles else build).append(b)
assetref=add('App/Assets.xcassets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "App/Assets.xcassets"; sourceTree = "<group>";')
refs.append(assetref)
assetbuild=add('build:App/Assets.xcassets', f'isa = PBXBuildFile; fileRef = {assetref};')
iconref=add('App/Rodopio.icon','isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = "App/Rodopio.icon"; sourceTree = "<group>";')
refs.append(iconref)
iconbuild=add('build:App/Rodopio.icon', f'isa = PBXBuildFile; fileRef = {iconref};')
app=add('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Ciranda.app; sourceTree = BUILT_PRODUCTS_DIR;')
testproduct=add('test-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CirandaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=add('products',f'isa = PBXGroup; children = {arr([app,testproduct])}; name = Products; sourceTree = "<group>";')
main=add('group',f'isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>";')
def configurations(name,base):
    configs=[]
    for mode in ['Debug','Release']:
        values=dict(base)
        values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        if mode=='Debug':values['ENABLE_TESTABILITY']='YES';values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        text=' '.join(f'{k} = {quoted(v)};' for k,v in values.items())
        configs.append(add(name+mode,f'isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {mode};'))
    return add(name+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
base={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','GCC_C_LANGUAGE_STANDARD':'c11','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'minimal'}
projectconfig=configurations('project',base)
appconfig=configurations('app',{'PRODUCT_BUNDLE_IDENTIFIER':'org.ciranda.prototype','PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_FILE':'App/Info.plist','SWIFT_OBJC_BRIDGING_HEADER':'App/Bridge.h','MARKETING_VERSION':'0.5.0','CURRENT_PROJECT_VERSION':'10','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','ASSETCATALOG_COMPILER_APPICON_NAME':'Rodopio'})
testconfig=configurations('test',{'PRODUCT_BUNDLE_IDENTIFIER':'org.ciranda.prototype.tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Ciranda.app/Ciranda','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
def phase(name,isa,files):return add(name,f'isa = {isa}; buildActionMask = 2147483647; files = {arr(files)}; runOnlyForDeploymentPostprocessing = 0;')
phases=[phase('sources','PBXSourcesBuildPhase',build),phase('frameworks','PBXFrameworksBuildPhase',[]),phase('resources','PBXResourcesBuildPhase',[assetbuild,iconbuild])]
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {appconfig}; buildPhases = {arr(phases)}; buildRules = (); dependencies = (); name = Ciranda; productName = Ciranda; productReference = {app}; productType = "com.apple.product-type.application";')
proxy=add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Ciranda;')
dep=add('dependency',f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
testphase=phase('test-sources','PBXSourcesBuildPhase',testbuild)
testframework=phase('test-frameworks','PBXFrameworksBuildPhase',[])
testtarget=add('test-target',f'isa = PBXNativeTarget; buildConfigurationList = {testconfig}; buildPhases = {arr([testphase,testframework])}; buildRules = (); dependencies = {arr([dep])}; name = CirandaTests; productName = CirandaTests; productReference = {testproduct}; productType = "com.apple.product-type.bundle.unit-test";')
projectid=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {projectconfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = pt; knownRegions = (pt,en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([target,testtarget])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(f'{i} = {{ {v} }};\n' for i,v in objects.items())+f'}}; rootObject = {projectid}; }}\n')
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def reference(t,n):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{t}" BuildableName="{n}" BlueprintName="{n.split(".")[0]}" ReferencedContainer="container:Ciranda.xcodeproj"/>'
(schemes/'Ciranda.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(target,'Ciranda.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(testtarget,'CirandaTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target,'Ciranda.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target,'Ciranda.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated',project)
