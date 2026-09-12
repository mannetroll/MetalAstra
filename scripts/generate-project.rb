#!/usr/bin/env ruby
# One-time deterministic project generation; building uses only Xcode.
require 'fileutils'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
FileUtils.mkdir_p('TurbulenceLab.xcodeproj/xcshareddata/xcschemes')
ids = {}; next_id = 100
id = ->(name) { ids[name] ||= begin next_id += 1; '%024X' % next_id end }
objects = []
add = ->(name, body) { objects << "#{id.call(name)} = { #{body} };" }
sources = Dir['TurbulenceLab/**/*.{swift,mm,metal}'].sort
headers = Dir['TurbulenceLab/**/*.h'].sort
(sources+headers).each do |file|
 type = {'.swift'=>'sourcecode.swift','.mm'=>'sourcecode.cpp.objcpp','.metal'=>'sourcecode.metal','.h'=>'sourcecode.c.h'}[File.extname(file)]
 add.call(file,"isa = PBXFileReference; lastKnownFileType = #{type}; path = \"#{file}\"; sourceTree = SOURCE_ROOT;")
 add.call("build:#{file}","isa = PBXBuildFile; fileRef = #{id.call(file)};") if sources.include?(file)
end
add.call('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = TurbulenceLab.app; sourceTree = BUILT_PRODUCTS_DIR;')
add.call('group',"isa = PBXGroup; children = (#{(sources+headers).map { |f| id.call(f) }.join(',')},#{id.call('products')}); sourceTree = \"<group>\";")
add.call('products',"isa = PBXGroup; children = (#{id.call('product')},#{id.call('testproduct')}); name = Products; sourceTree = \"<group>\";")
add.call('sources',"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{sources.map { |f| id.call("build:#{f}") }.join(',')}); runOnlyForDeploymentPostprocessing = 0;")
add.call('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add.call('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
%w[Debug Release].each do |mode|
 settings = {
 'PRODUCT_NAME'=>'TurbulenceLab','PRODUCT_BUNDLE_IDENTIFIER'=>'org.metalastra.TurbulenceLab','MACOSX_DEPLOYMENT_TARGET'=>'15.0',
 'SDKROOT'=>'macosx','ARCHS'=>'arm64','SWIFT_VERSION'=>'5.0','CLANG_CXX_LANGUAGE_STANDARD'=>'c++17',
 'CLANG_ENABLE_MODULES'=>'YES','CLANG_ENABLE_OBJC_ARC'=>'YES','ENABLE_HARDENED_RUNTIME'=>'YES','CODE_SIGN_STYLE'=>'Automatic',
 'GENERATE_INFOPLIST_FILE'=>'YES','INFOPLIST_KEY_CFBundleDisplayName'=>'Turbulence Lab','INFOPLIST_KEY_LSApplicationCategoryType'=>'public.app-category.education',
 'INFOPLIST_KEY_NSPrincipalClass'=>'NSApplication','INFOPLIST_KEY_NSHighResolutionCapable'=>'YES','MARKETING_VERSION'=>'1.0','CURRENT_PROJECT_VERSION'=>'1',
 'SWIFT_OBJC_BRIDGING_HEADER'=>'TurbulenceLab/VkFFTBridge/VkFFTBridge.h','HEADER_SEARCH_PATHS'=>'$(SRCROOT)/Vendor $(SRCROOT)/Vendor/VkFFT',
 'OTHER_LDFLAGS'=>'-framework Metal -framework MetalKit -framework QuartzCore -framework Foundation',
 'SWIFT_OPTIMIZATION_LEVEL'=>mode=='Release' ? '-O' : '-Onone','GCC_OPTIMIZATION_LEVEL'=>mode=='Release' ? '3':'0',
 'MTL_FAST_MATH'=>'NO','ENABLE_TESTABILITY'=>'YES','DEBUG_INFORMATION_FORMAT'=>mode=='Release' ? 'dwarf-with-dsym':'dwarf',
 'SWIFT_COMPILATION_MODE'=>mode=='Release' ? 'wholemodule':'singlefile'
 }
 add.call("config:#{mode}","isa = XCBuildConfiguration; buildSettings = { #{settings.map { |k,v| "#{k} = \"#{v}\";" }.join(' ')} }; name = #{mode};")
 testsettings = settings.merge('PRODUCT_NAME'=>'TurbulenceLabTests','PRODUCT_BUNDLE_IDENTIFIER'=>'org.metalastra.TurbulenceLabTests','CODE_SIGNING_ALLOWED'=>'NO')
 add.call("testconfig:#{mode}","isa = XCBuildConfiguration; buildSettings = { #{testsettings.map { |k,v| "#{k} = \"#{v}\";" }.join(' ')} }; name = #{mode};")
 add.call("projectconfig:#{mode}","isa = XCBuildConfiguration; buildSettings = {}; name = #{mode};")
end
add.call('configlist',"isa = XCConfigurationList; buildConfigurations = (#{id.call('config:Debug')},#{id.call('config:Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add.call('projectconfiglist',"isa = XCConfigurationList; buildConfigurations = (#{id.call('projectconfig:Debug')},#{id.call('projectconfig:Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add.call('target',"isa = PBXNativeTarget; buildConfigurationList = #{id.call('configlist')}; buildPhases = (#{id.call('sources')},#{id.call('frameworks')},#{id.call('resources')}); buildRules = (); dependencies = (); name = TurbulenceLab; productName = TurbulenceLab; productReference = #{id.call('product')}; productType = \"com.apple.product-type.application\";")
test_sources = sources.select { |f| f =~ /MetalResources|SpectralSolver|SimulationConfig|NumericalTests|\.metal$|\.mm$/ }
add.call('testwrapper','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = XCTest/SolverTests.swift; sourceTree = SOURCE_ROOT;')
add.call('testwrapperbuild',"isa = PBXBuildFile; fileRef = #{id.call('testwrapper')};")
test_sources.each { |f| add.call("testbuild:#{f}","isa = PBXBuildFile; fileRef = #{id.call(f)};") }
add.call('testsources',"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{test_sources.map { |f| id.call("testbuild:#{f}") }.join(',')},#{id.call('testwrapperbuild')}); runOnlyForDeploymentPostprocessing = 0;")
add.call('testframeworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add.call('testconfiglist',"isa = XCConfigurationList; buildConfigurations = (#{id.call('testconfig:Debug')},#{id.call('testconfig:Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add.call('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = TurbulenceLabTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add.call('testtarget',"isa = PBXNativeTarget; buildConfigurationList = #{id.call('testconfiglist')}; buildPhases = (#{id.call('testsources')},#{id.call('testframeworks')}); buildRules = (); dependencies = (); name = TurbulenceLabTests; productName = TurbulenceLabTests; productReference = #{id.call('testproduct')}; productType = \"com.apple.product-type.bundle.unit-test\";")
add.call('project',"isa = PBXProject; attributes = { LastUpgradeCheck = 2630; }; buildConfigurationList = #{id.call('projectconfiglist')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; knownRegions = (en,Base); mainGroup = #{id.call('group')}; productRefGroup = #{id.call('products')}; projectDirPath = \"\"; projectRoot = \"\"; targets = (#{id.call('target')},#{id.call('testtarget')});")
File.write('TurbulenceLab.xcodeproj/project.pbxproj',"// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n#{objects.join("\n")}\n}; rootObject = #{id.call('project')}; }\n")
File.write('TurbulenceLab.xcodeproj/xcshareddata/xcschemes/TurbulenceLab.xcscheme',<<~XML)
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
<TestAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{id.call('testtarget')}" BuildableName="TurbulenceLabTests.xctest" BlueprintName="TurbulenceLabTests" ReferencedContainer="container:TurbulenceLab.xcodeproj"/></TestableReference></Testables></TestAction>
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{id.call('target')}" BuildableName="TurbulenceLab.app" BlueprintName="TurbulenceLab" ReferencedContainer="container:TurbulenceLab.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{id.call('target')}" BuildableName="TurbulenceLab.app" BlueprintName="TurbulenceLab" ReferencedContainer="container:TurbulenceLab.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{id.call('target')}" BuildableName="TurbulenceLab.app" BlueprintName="TurbulenceLab" ReferencedContainer="container:TurbulenceLab.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
XML
