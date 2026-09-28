#!/usr/bin/env python3
"""Render current production SwiftUI views with explicit fictional status fixtures.

This is an offscreen visual guide, never a patch/restore demonstration or benchmark.
The real ContentView uses its model injection seam with automatic startup disabled.
A disposable bundle's doctor-only fixture supplies states; no real WeChat is read.
"""
from pathlib import Path
import hashlib, json, plistlib, sys, uuid

sys.path.insert(0, str(Path(__file__).resolve().parent / 'accept'))
from _common import run as common_run, xcode_env

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/current-guide'
OUT = ROOT / 'docs/demo'
WORK.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
ENV = xcode_env()
VERSION = plistlib.loads((ROOT / 'Info.plist').read_bytes())['CFBundleShortVersionString']
SOURCE_HASHES = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'Sources').glob('*.swift')}

def run(*args, **kwargs):
    result = common_run([str(x) for x in args], env=kwargs.pop('env', ENV), **kwargs)
    if result.strip():
        print(result.strip())

(WORK / 'Capture.swift').write_text(r'''
import AppKit
import SwiftUI
extension Notification.Name { static let consoleRefresh = Notification.Name("consoleRefresh") }
@main struct Capture {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[2])
    app.applicationIconImage.setName(NSImage.applicationIconName)
    app.appearance = NSAppearance(named: .aqua)
    Task { @MainActor in
      do {
        let bundleID = Bundle.main.bundleIdentifier!
        precondition(bundleID.hasPrefix("io.github.zengtianli.unrevoke.offscreen-guide."))
        precondition(Engine.weChatPath == ProcessInfo.processInfo.environment["UNREVOKE_GUIDE_TARGET"])
        defer { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
        let model = AppModel(confirmAction: { _, _, _ in false })
        model.autoRepatch = false
        defer { model.stop() }
        await model.refresh()
        guard model.status != nil, model.errorMessage == nil else {
          throw NSError(domain: "Guide", code: 1, userInfo: [NSLocalizedDescriptionKey: model.errorMessage ?? "Missing fixture state"])
        }
        let view = NSHostingView(rootView: ContentView(model: model, automaticallyStart: false)
          .transaction { $0.animation = nil; $0.disablesAnimations = true }
          .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 640)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        precondition(!window.isVisible && !window.isKeyWindow)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
      } catch {
        fputs("Guide render failed: \(error)\n", stderr)
        exit(1)
      }
      exit(0)
    }
    app.run()
  }
}
''')
APP = WORK / 'Guide.app'
(APP / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(APP / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
(APP / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':f'io.github.zengtianli.unrevoke.offscreen-guide.{uuid.uuid4().hex}','CFBundleExecutable':'Guide','CFBundlePackageType':'APPL','CFBundleShortVersionString':VERSION,'LSUIElement':True}))
target = WORK / 'WeChat-fixture.app'
target.mkdir(exist_ok=True)
engine = APP / 'Contents/Resources/wechattweak'
engine.write_text('''#!/bin/sh
set -eu
[ "$1" = "doctor" ] && [ "$2" = "-a" ] && [ "$3" = "$UNREVOKE_GUIDE_TARGET" ] || exit 91
cat "$UNREVOKE_GUIDE_FIXTURE"
''')
engine.chmod(0o755)
run('xcrun','swiftc','-parse-as-library',ROOT/'Sources/Models.swift',ROOT/'Sources/Engine.swift',ROOT/'Sources/ViewModel.swift',ROOT/'Sources/ContentView.swift',WORK/'Capture.swift','-o',APP/'Contents/MacOS/Guide')
run('xcrun','swiftc',ROOT/'scripts/demo-caption.swift','-o',WORK/'caption')
scenes = [
    ('unprotected','01 · 检查当前状态','未打补丁时，主按钮显示「开启防撤回」','虚构状态 · 仅展示当前界面，不执行写入'),
    ('protected','02 · 两项结果分别说明','防撤回与拦截更新均生效时，可重新检查或还原','虚构状态 · 未操作真实微信或消息'),
    ('antiRevokeOnly','03 · 防撤回已经生效','App Store 版没有可拦截的内置更新器','虚构状态 · 两项功能独立，不必重复打补丁'),
]
segments=[]; cues=['WEBVTT\n']
for i,(state,title,line1,line2) in enumerate(scenes):
    fixture={'overall':state,'build':'示例版本','app_path':str(target),'config_known':True,'config_targets':['revoke','update'],'running':False,'writable':True,'signature':'valid','sip':'enabled','entitlements_ok':True,'entitlement_key_count':15,'anti_revoke_keeptip':'pristine' if state=='unprotected' else 'patched','update_block':'notApplicable' if state=='antiRevokeOnly' else ('pristine' if state=='unprotected' else 'patched'),'update_source':'App Store' if state=='antiRevokeOnly' else 'config'}
    spec=WORK/f'{state}.json';spec.write_text(json.dumps(fixture,ensure_ascii=False))
    image=OUT/f'current-{state}.png'
    run(APP/'Contents/MacOS/Guide',image,ROOT/'icon/AppIcon.png','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN','-weChatPath',target,'-everProtected','NO',env={**ENV,'UNREVOKE_GUIDE_FIXTURE':str(spec),'UNREVOKE_GUIDE_TARGET':str(target)})
    caption=WORK/f'{state}-caption.json';caption.write_text(json.dumps({'title':title,'line1':line1,'line2':line2},ensure_ascii=False))
    overlay=WORK/f'{state}-overlay.png';run(WORK/'caption',caption,overlay)
    segment=WORK/f'{state}.mp4'
    run('ffmpeg','-v','error','-loop','1','-i',image,'-loop','1','-i',overlay,'-filter_complex','[0:v]scale=620:640,pad=720:840:50:65:color=0xf6f8f3,setsar=1[body];[body][1:v]overlay=0:0:shortest=1[v]','-map','[v]','-t','7','-r','24','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart','-y',segment)
    segments.append(segment)
    cues.append(f'00:00:{i*7:02}.000 --> 00:00:{(i+1)*7:02}.000\n{line1}\n{line2}\n')
concat=WORK/'concat.txt';concat.write_text(''.join(f"file '{p}'\n" for p in segments))
run('ffmpeg','-v','error','-f','concat','-safe','0','-i',concat,'-c','copy','-movflags','+faststart','-y',OUT/'current-guide.mp4')
(OUT/'current-guide.vtt').write_text('\n'.join(cues))
sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'Sources').glob('*.swift')}
assert sources == SOURCE_HASHES, 'Sources changed during rendering; rerun with stable inputs'
assert plistlib.loads((ROOT/'Info.plist').read_bytes())['CFBundleShortVersionString'] == VERSION, 'Version changed during rendering'
files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('current-*') if p.suffix in ('.png','.mp4','.vtt')}
(OUT/'current-guide.json').write_text(json.dumps({'version':VERSION,'method':'Current production ContentView rendered offscreen with fictional DoctorStatus fixtures using the model injection seam and automaticallyStart:false. Isolated bundle and doctor-only fixture executable; no real WeChat access, patch/restore, network request, system clipboard, input synthesis or foreground window. Not a performance measurement or real patch demonstration.','source_sha256':sources,'duration_seconds':21,'files':files},ensure_ascii=False,indent=2)+'\n')
print('Current UI guide rendered:',OUT/'current-guide.mp4')
