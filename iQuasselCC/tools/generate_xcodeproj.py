#!/usr/bin/env python3
"""Generates iQuasselCC.xcodeproj from the source tree.

Run from the iQuasselCC directory:  python3 tools/generate_xcodeproj.py
(Alternatively use XcodeGen with project.yml.)
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "iQuasselCC"
TESTS = "iQuasselCCTests"
BUNDLE_ID = "app.iquasselcc.client"
DEPLOYMENT = "17.0"


def uid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(s):
    if s and all(c.isalnum() or c in "._/" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace('"', '\\"') + '"'


def collect(folder, exts):
    out = []
    base = os.path.join(ROOT, folder)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = sorted(d for d in dirnames if not d.endswith(".xcassets"))
        for f in sorted(filenames):
            if os.path.splitext(f)[1] in exts:
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
        for d in sorted(os.listdir(dirpath)):
            if d.endswith(".xcassets"):
                out.append(os.path.relpath(os.path.join(dirpath, d), ROOT))
    return sorted(set(out))


app_files = collect(APP, {".swift", ".plist"})
test_files = collect(TESTS, {".swift"})
protocol_sources = [f for f in app_files if (f.startswith(APP + "/Protocol/") and f.endswith(".swift")) or f == APP + "/Model/Network.swift"]

objects = {}


def add(oid, body):
    objects[oid] = body


# ---- file references and groups
groups = {}  # path -> list of child ids


def ensure_group(path):
    if path in groups:
        return uid("group", path)
    groups[path] = []
    parent = os.path.dirname(path)
    if path != "":
        ensure_group(parent)
        groups[parent].append(uid("group", path))
    return uid("group", path)


def file_type(path):
    ext = os.path.splitext(path)[1]
    return {
        ".swift": "sourcecode.swift",
        ".plist": "text.plist.xml",
        ".xcassets": "folder.assetcatalog",
    }.get(ext, "text")


all_files = app_files + test_files
for f in all_files:
    ensure_group(os.path.dirname(f))
    fid = uid("file", f)
    groups[os.path.dirname(f)].append(fid)
    add(fid, "{isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; }"
        % (file_type(f), q(os.path.basename(f))))

products_group = uid("group", "Products")
app_product = uid("product", APP)
test_product = uid("product", TESTS)
add(app_product, "{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; }" % APP)
add(test_product, "{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = %s.xctest; sourceTree = BUILT_PRODUCTS_DIR; }" % TESTS)
add(products_group, "{isa = PBXGroup; children = (%s, %s, ); name = Products; sourceTree = \"<group>\"; }" % (app_product, test_product))

for path, children in groups.items():
    gid = uid("group", path)
    if path == "":
        kids = children + [products_group]
        add(gid, "{isa = PBXGroup; children = (%s); sourceTree = \"<group>\"; }" % "".join(k + ", " for k in kids))
    else:
        add(gid, "{isa = PBXGroup; children = (%s); path = %s; sourceTree = \"<group>\"; }"
            % ("".join(k + ", " for k in children), q(os.path.basename(path))))

# ---- build files and phases


def build_phase(kind, target, files):
    pid = uid("phase", kind, target)
    ids = []
    for f in files:
        bid = uid("build", target, kind, f)
        add(bid, "{isa = PBXBuildFile; fileRef = %s; }" % uid("file", f))
        ids.append(bid)
    isa = {"sources": "PBXSourcesBuildPhase", "resources": "PBXResourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase"}[kind]
    add(pid, "{isa = %s; buildActionMask = 2147483647; files = (%s); runOnlyForDeploymentPostprocessing = 0; }"
        % (isa, "".join(i + ", " for i in ids)))
    return pid


app_sources = [f for f in app_files if f.endswith(".swift")]
app_resources = [f for f in app_files if f.endswith(".xcassets")]
app_phases = [build_phase("sources", APP, app_sources), build_phase("frameworks", APP, []),
              build_phase("resources", APP, app_resources)]
test_phases = [build_phase("sources", TESTS, protocol_sources + test_files), build_phase("frameworks", TESTS, []),
               build_phase("resources", TESTS, [])]


def settings_block(d):
    return "{" + "".join("%s = %s; " % (k, v if v.startswith("(") else q(v)) for k, v in sorted(d.items())) + "}"


common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "DEVELOPMENT_LANGUAGE": "en",
}
project_debug = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "ENABLE_TESTABILITY": "YES",
                                "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                                "GCC_OPTIMIZATION_LEVEL": "0"})
project_release = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule",
                                  "VALIDATE_PRODUCT": "YES"})

app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "INFOPLIST_FILE": APP + "/Resources/Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO",
    "LD_RUNPATH_SEARCH_PATHS": "(\"$(inherited)\", \"@executable_path/Frameworks\", )",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "TARGETED_DEVICE_FAMILY": "1",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "ENABLE_PREVIEWS": "YES",
}
test_settings = {
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "TARGETED_DEVICE_FAMILY": "1",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
}


def config_list(owner, debug, release):
    d = uid("config", owner, "Debug")
    r = uid("config", owner, "Release")
    add(d, "{isa = XCBuildConfiguration; buildSettings = %s; name = Debug; }" % settings_block(debug))
    add(r, "{isa = XCBuildConfiguration; buildSettings = %s; name = Release; }" % settings_block(release))
    lid = uid("configlist", owner)
    add(lid, "{isa = XCConfigurationList; buildConfigurations = (%s, %s, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }" % (d, r))
    return lid


app_target = uid("target", APP)
test_target = uid("target", TESTS)
add(app_target, "{isa = PBXNativeTarget; buildConfigurationList = %s; buildPhases = (%s); buildRules = (); dependencies = (); name = %s; productName = %s; productReference = %s; productType = \"com.apple.product-type.application\"; }"
    % (config_list(APP, app_settings, app_settings), "".join(p + ", " for p in app_phases), APP, APP, app_product))
add(test_target, "{isa = PBXNativeTarget; buildConfigurationList = %s; buildPhases = (%s); buildRules = (); dependencies = (); name = %s; productName = %s; productReference = %s; productType = \"com.apple.product-type.bundle.unit-test\"; }"
    % (config_list(TESTS, test_settings, test_settings), "".join(p + ", " for p in test_phases), TESTS, TESTS, test_product))

project = uid("project")
add(project, "{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; }; buildConfigurationList = %s; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); mainGroup = %s; productRefGroup = %s; projectDirPath = \"\"; projectRoot = \"\"; targets = (%s, %s, ); }"
    % (config_list("project", project_debug, project_release), uid("group", ""), products_group, app_target, test_target))

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for k in sorted(objects):
    out.append("\t\t%s = %s;" % (k, objects[k]))
out += ["\t};", "\trootObject = %s;" % project, "}", ""]

proj_dir = os.path.join(ROOT, APP + ".xcodeproj")
os.makedirs(os.path.join(proj_dir, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as fh:
    fh.write("\n".join(out))

scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app}" BuildableName = "{name}.app" BlueprintName = "{name}" ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tests}" BuildableName = "{testname}.xctest" BlueprintName = "{testname}" ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app}" BuildableName = "{name}.app" BlueprintName = "{name}" ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("{app}", app_target).replace("{tests}", test_target).replace("{name}", APP).replace("{testname}", TESTS)
with open(os.path.join(proj_dir, "xcshareddata", "xcschemes", APP + ".xcscheme"), "w") as fh:
    fh.write(scheme)

print("Generated %s with %d app files and %d test files" % (proj_dir, len(app_sources), len(test_files)))
