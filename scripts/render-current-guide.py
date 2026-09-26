#!/usr/bin/env python3
"""Render current production SwiftUI views with explicit fictional status fixtures.

This is an offscreen visual guide, never a patch/restore demonstration or benchmark.
The temporary compilation disables ContentView's start task; no Engine method is run.
"""
from pathlib import Path
import hashlib, json, os, subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/current-guide'
OUT = ROOT / 'docs/demo'
WORK.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)

view = (ROOT / 'Sources/ContentView.swift').read_text()
assert view.count('.task { model.start() }') == 1
(WORK / 'ContentView.swift').write_text(view.replace('.task { model.start() }', ''))
model = (ROOT / 'Sources/ViewModel.swift').read_text()
anchor = 'launchAtLogin = SMAppService.mainApp.status == .enabled'
assert anchor in model.split('// MARK: - 生命周期')[0]
model = model.replace(anchor, anchor + '''
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        status = try! decoder.decode(DoctorStatus.self, from: Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNREVOKE_GUIDE_FIXTURE"]!)))
        autoRepatch = false
''', 1)
(WORK / 'ViewModel.swift').write_text(model)
(WORK / 'Capture.swift').write_text(r'''
import AppKit
import SwiftUI
extension Notification.Name { static let consoleRefresh = Notification.Name("consoleRefresh") }
@main struct Capture {
  @MainActor static func main() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[2])
    app.applicationIconImage.setName(NSImage.applicationIconName)
    app.appearance = NSAppearance(named: .aqua)
    let view = NSHostingView(rootView: ContentView().environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
    view.frame = NSRect(x: 0, y: 0, width: 620, height: 640)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
  }
}
''')
APP = WORK / 'Guide.app'
(APP / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
import plistlib
(APP / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.github.zengtianli.unrevoke.offscreen-guide','CFBundleExecutable':'Guide','CFBundlePackageType':'APPL'}))
run('xcrun','swiftc','-parse-as-library',ROOT/'Sources/Models.swift',ROOT/'Sources/Engine.swift',WORK/'ViewModel.swift',WORK/'ContentView.swift',WORK/'Capture.swift','-o',APP/'Contents/MacOS/Guide')
run('xcrun','swiftc',ROOT/'scripts/demo-caption.swift','-o',WORK/'caption')
scenes = [
    ('unprotected','01 · 检查当前状态','未打补丁时，主按钮显示「开启防撤回」','虚构状态 · 仅展示当前界面，不执行写入'),
    ('protected','02 · 两项结果分别说明','防撤回与拦截更新均生效时，可重新检查或还原','虚构状态 · 未操作真实微信或消息'),
    ('antiRevokeOnly','03 · 防撤回已经生效','App Store 版没有可拦截的内置更新器','虚构状态 · 两项功能独立，不必重复打补丁'),
]
segments=[]; cues=['WEBVTT\n']
for i,(state,title,line1,line2) in enumerate(scenes):
    fixture={'overall':state,'build':'示例版本','app_path':'/Applications/WeChat.app','config_known':True,'config_targets':['revoke','update'],'running':False,'writable':True,'signature':'valid','sip':'enabled','entitlements_ok':True,'entitlement_key_count':15,'anti_revoke_keeptip':'pristine' if state=='unprotected' else 'patched','update_block':'notApplicable' if state=='antiRevokeOnly' else ('pristine' if state=='unprotected' else 'patched'),'update_source':'App Store' if state=='antiRevokeOnly' else 'config'}
    spec=WORK/f'{state}.json';spec.write_text(json.dumps(fixture,ensure_ascii=False))
    image=OUT/f'current-{state}.png'
    run(APP/'Contents/MacOS/Guide',image,ROOT/'icon/AppIcon.png','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN',env={**os.environ,'UNREVOKE_GUIDE_FIXTURE':str(spec)})
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
files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('current-*') if p.suffix in ('.png','.mp4','.vtt')}
(OUT/'current-guide.json').write_text(json.dumps({'version':'1.0.9','method':'Current production ContentView rendered offscreen with fictional DoctorStatus fixtures; start task disabled in temporary harness, no Engine operation, no system clipboard, input synthesis or foreground window. Not a performance measurement or real patch demonstration.','source_sha256':sources,'duration_seconds':21,'files':files},ensure_ascii=False,indent=2)+'\n')
print('Current UI guide rendered:',OUT/'current-guide.mp4')
