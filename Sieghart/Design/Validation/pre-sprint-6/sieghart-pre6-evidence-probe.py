from pathlib import Path
import shutil, subprocess
workspace=Path('/private/tmp/sieghart-pre6-build-snapshot/SourceWorkspace')
link=workspace/'Tests/SwiftTesting'
real=Path('/Users/antoniopaesdeandrade/Documents/ChatGPT/MyDude/Sieghart/Tests/SwiftTesting')
assert link.is_symlink() and link.resolve()==real
link.unlink(); link.mkdir()
try:
 for source in real.rglob('*.swift'):
  target=link/source.relative_to(real); target.parent.mkdir(parents=True,exist_ok=True)
  if source.name=='CompanionNativeTests.swift':
   target.write_text(source.read_text()+Path('/private/tmp/sieghart-pre6-artwork-probe.swift').read_text())
  else: target.symlink_to(source)
 command=['xcodebuild','-project',str(workspace/'Sieghart.xcodeproj'),'-scheme','Sieghart-Checks','-testPlan','Sieghart-Complete','-destination','platform=macOS,arch=arm64','-derivedDataPath','/private/tmp/sieghart-pre6-build-snapshot','-resultBundlePath','/private/tmp/sieghart-pre6-evidence-probe.xcresult','-parallel-testing-enabled','NO','-maximum-parallel-testing-workers','1','-only-testing:SieghartTests/PreS6EvidenceProbe','-test-iterations','2','-test-repetition-relaunch-enabled','NO','test']
 with open('/private/tmp/sieghart-pre6-evidence-probe.log','w') as log:
  result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
 print('Expected negative-control exit 65; actual:',result.returncode)
 assert result.returncode==65
finally:
 shutil.rmtree(link); link.symlink_to(real,target_is_directory=True)
