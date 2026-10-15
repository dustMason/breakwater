#!/usr/bin/env python3
"""Generate the checked-in Xcode project without a third-party generator."""
from pathlib import Path
import hashlib
r=Path(__file__).resolve().parents[1]
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
objects={}
def put(name,body):objects[uid(name)]=body;return uid(name)
def q(s):return '"'+s+'"'
def arr(xs):return '('+','.join(xs)+',)'
sources=sorted([*r.glob('App/*.swift'),*r.glob('AudioCore/*.cpp')])
refs=[];builds=[]
for p in sources:
 name=str(p.relative_to(r));typ='sourcecode.swift' if p.suffix=='.swift' else 'sourcecode.cpp.cpp'
 ref=put(name,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(name)}; sourceTree = SOURCE_ROOT;');refs.append(ref)
 builds.append(put(name+'-build',f'isa = PBXBuildFile; fileRef = {ref};'))
samples=put('samples','isa = PBXFileReference; lastKnownFileType = folder; path = Samples; sourceTree = SOURCE_ROOT;')
resource=put('samples-build',f'isa = PBXBuildFile; fileRef = {samples};')
assets=put('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assetBuild=put('assets-build',f'isa = PBXBuildFile; fileRef = {assets};')
product=put('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Breakwater.app; sourceTree = BUILT_PRODUCTS_DIR;')
uiProduct=put('ui-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = BreakwaterUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
uiRef=put('ui-test-file','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/BreakwaterUITests.swift; sourceTree = SOURCE_ROOT;')
uiBuild=put('ui-test-build',f'isa = PBXBuildFile; fileRef = {uiRef};')
products=put('products',f'isa = PBXGroup; children = {arr([product,uiProduct])}; name = Products; sourceTree = "<group>";')
main=put('main',f'isa = PBXGroup; children = {arr(refs+[samples,assets,uiRef,products])}; sourceTree = "<group>";')
src=put('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')
res=put('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([resource,assetBuild])}; runOnlyForDeploymentPostprocessing = 0;')
frameworks=put('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
uiSrc=put('ui-sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr([uiBuild])}; runOnlyForDeploymentPostprocessing = 0;')
common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','CLANG_CXX_LANGUAGE_STANDARD':'"c++17"','CLANG_CXX_LIBRARY':'"libc++"','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'2','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','ENABLE_USER_SCRIPT_SANDBOXING':'YES','CODE_SIGN_STYLE':'Automatic'}
app={'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','PRODUCT_NAME':'"$(TARGET_NAME)"','PRODUCT_BUNDLE_IDENTIFIER':'com.dustmason.breakwater','INFOPLIST_FILE':'App/Info.plist','SWIFT_OBJC_BRIDGING_HEADER':'"App/Breakwater-Bridging-Header.h"','HEADER_SEARCH_PATHS':'"$(SRCROOT)/AudioCore"','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'6','SWIFT_EMIT_LOC_STRINGS':'YES','ENABLE_PREVIEWS':'YES'}
ui={'PRODUCT_NAME':'"$(TARGET_NAME)"','PRODUCT_BUNDLE_IDENTIFIER':'com.dustmason.breakwater.uitests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'Breakwater'}
def configs(name,extra):
 ids=[]
 for cfg in ['Debug','Release']:
  values={**common,**extra,'SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if cfg=='Debug' else '"-O"','GCC_OPTIMIZATION_LEVEL':'0' if cfg=='Debug' else 's','DEBUG_INFORMATION_FORMAT':'dwarf' if cfg=='Debug' else '"dwarf-with-dsym"'}
  if cfg=='Debug':values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG';values['GCC_PREPROCESSOR_DEFINITIONS']='("DEBUG=1","$(inherited)")'
  ids.append(put(name+cfg,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+v+';' for k,v in values.items())+'}; name = '+cfg+';'))
 return put(name+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projConfig=configs('project',{});appConfig=configs('app',app);uiConfig=configs('ui',ui)
target=put('target',f'isa = PBXNativeTarget; buildConfigurationList = {appConfig}; buildPhases = {arr([src,frameworks,res])}; buildRules = (); dependencies = (); name = Breakwater; productName = Breakwater; productReference = {product}; productType = "com.apple.product-type.application";')
proxy=put('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Breakwater;')
dep=put('dependency',f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
uiTarget=put('ui-target',f'isa = PBXNativeTarget; buildConfigurationList = {uiConfig}; buildPhases = {arr([uiSrc])}; buildRules = (); dependencies = {arr([dep])}; name = BreakwaterUITests; productName = BreakwaterUITests; productReference = {uiProduct}; productType = "com.apple.product-type.bundle.ui-testing";')
project=put('project',f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2700; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 27.0;}}; {uiTarget} = {{CreatedOnToolsVersion = 27.0; TestTargetID = {target};}};}};}}; buildConfigurationList = {projConfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([target,uiTarget])};')
out=r/'Breakwater.xcodeproj';out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(k+' = {'+v+'};\n' for k,v in objects.items())+'}; rootObject = '+project+'; }\n')
scheme=out/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Breakwater.app" BlueprintName="Breakwater" ReferencedContainer="container:Breakwater.xcodeproj"/>'
uref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uiTarget}" BuildableName="BreakwaterUITests.xctest" BlueprintName="BreakwaterUITests" ReferencedContainer="container:Breakwater.xcodeproj"/>'
(scheme/'Breakwater.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{uref}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated Breakwater.xcodeproj')
