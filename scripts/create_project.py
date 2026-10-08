"""Generate the checked-in dependency-free Xcode project using only Python's stdlib."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
objects = []
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, text):
    objects.append(f'\t\t{uid(name)} = {{ {text} }};')
    return uid(name)
def ref(name):
    return uid(name)
def ids(*names):
    return '(' + ', '.join(map(ref, names)) + ',)'

add('swift', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoToLivePhotoApp.swift; sourceTree = "<group>";')
add('testswift', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LivePhotoIntegrationTests.swift; sourceTree = "<group>";')
add('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = VideoToLivePhoto.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('testapp', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = VideoToLivePhotoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add('buildswift', f'isa = PBXBuildFile; fileRef = {ref("swift")};')
add('buildtestswift', f'isa = PBXBuildFile; fileRef = {ref("testswift")};')
add('appgroup', f'isa = PBXGroup; children = {ids("swift")}; path = VideoToLivePhoto; sourceTree = "<group>";')
add('testgroup', f'isa = PBXGroup; children = {ids("testswift")}; path = VideoToLivePhotoTests; sourceTree = "<group>";')
add('products', f'isa = PBXGroup; children = {ids("app", "testapp")}; name = Products; sourceTree = "<group>";')
add('root', f'isa = PBXGroup; children = {ids("appgroup", "testgroup", "products")}; sourceTree = "<group>";')
for prefix, build in [('app', 'buildswift'), ('test', 'buildtestswift')]:
    add(prefix+'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(build)}; runOnlyForDeploymentPostprocessing = 0;')
    for phase in ('frameworks', 'resources'):
        add(prefix+phase, f'isa = PBX{phase.title()}BuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("apptarget")}; remoteInfo = VideoToLivePhoto;')
add('dependency', f'isa = PBXTargetDependency; target = {ref("apptarget")}; targetProxy = {ref("proxy")};')
for prefix, name, product, kind in [('app', 'VideoToLivePhoto', 'app', 'application'), ('test', 'VideoToLivePhotoTests', 'testapp', 'bundle.unit-test')]:
    dependency = ids('dependency') if prefix == 'test' else '()'
    add(prefix+'target', f'isa = PBXNativeTarget; buildConfigurationList = {ref(prefix+"configs")}; buildPhases = {ids(prefix+"sources", prefix+"frameworks", prefix+"resources")}; buildRules = (); dependencies = {dependency}; name = {name}; productName = {name}; productReference = {ref(product)}; productType = "com.apple.product-type.{kind}";')
for level in ('project', 'app', 'test'):
    for mode in ('Debug', 'Release'):
        settings = {
            'project': 'CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 16.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; GCC_WARN_UNUSED_VARIABLE = YES; CLANG_WARN_DOCUMENTATION_COMMENTS = YES;',
            'app': '''CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_KEY_CFBundleDisplayName = "实况转换";
                INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "将转换后的实况照片添加到你的相册，不读取其他照片。";
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
                INFOPLIST_KEY_UILaunchScreen_Generation = YES;
                INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
                PRODUCT_BUNDLE_IDENTIFIER = com.personal.VideoToLivePhoto;
                PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
                SUPPORTS_MACCATALYST = NO; MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1;''',
            'test': '''CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES;
                PRODUCT_BUNDLE_IDENTIFIER = com.personal.VideoToLivePhotoTests;
                PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
                TEST_HOST = "$(BUILT_PRODUCTS_DIR)/VideoToLivePhoto.app/VideoToLivePhoto";
                BUNDLE_LOADER = "$(TEST_HOST)";'''
        }[level]
        if mode == 'Debug':
            settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;'
        else:
            settings += ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        add(level+mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
    add(level+'configs', f'isa = XCConfigurationList; buildConfigurations = {ids(level+"Debug", level+"Release")}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('project', f'''isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{
    {ref("apptarget")} = {{ CreatedOnToolsVersion = 16.0; }};
    {ref("testtarget")} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {ref("apptarget")}; }};
}}; }}; buildConfigurationList = {ref("projectconfigs")}; compatibilityVersion = "Xcode 14.0";
    developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base,);
    mainGroup = {ref("root")}; productRefGroup = {ref("products")}; projectDirPath = "";
    projectRoot = ""; targets = {ids("apptarget", "testtarget")};''')
(root/'VideoToLivePhoto.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {ref("project")};\n}}\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('apptarget')}" BuildableName="VideoToLivePhoto.app" BlueprintName="VideoToLivePhoto" ReferencedContainer="container:VideoToLivePhoto.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('testtarget')}" BuildableName="VideoToLivePhotoTests.xctest" BlueprintName="VideoToLivePhotoTests" ReferencedContainer="container:VideoToLivePhoto.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('apptarget')}" BuildableName="VideoToLivePhoto.app" BlueprintName="VideoToLivePhoto" ReferencedContainer="container:VideoToLivePhoto.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('apptarget')}" BuildableName="VideoToLivePhoto.app" BlueprintName="VideoToLivePhoto" ReferencedContainer="container:VideoToLivePhoto.xcodeproj"/></BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(root/'VideoToLivePhoto.xcodeproj/xcshareddata/xcschemes/VideoToLivePhoto.xcscheme').write_text(scheme)
