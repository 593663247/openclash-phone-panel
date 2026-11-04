"""Validate standard Windows ZIP and opkg archive structure without installing."""
import hashlib,io,pathlib,subprocess,tarfile,tempfile,zipfile,sys
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='phone-package-') as temp:
 subprocess.run([sys.executable,str(root/'scripts/build-package.py'),'--output',temp],cwd=root,check=True,stdout=subprocess.DEVNULL)
 out=pathlib.Path(temp)
 rv=subprocess.run(['ruby','-e','print RUBY_VERSION'],capture_output=True,text=True).stdout.strip()
 if tuple(int(x) for x in (rv or '0.0').split('.')[:2])>=(2,7):
  subprocess.run(['ruby',str(root/'tests/check-update-package.rb'),str(out/'phone-panel-update.tar.gz')],cwd=out,check=True)
 else:
  print('SKIP: update package Ruby check needs Ruby >= 2.7, found '+(rv or 'none'))
 bundle=next(out.glob('*Windows.zip'))
 with zipfile.ZipFile(bundle) as z:
  assert z.testzip() is None
  for name in z.namelist():
   assert name.isascii() and '/' not in name and '\\' not in name and '__MACOSX' not in name
   assert z.getinfo(name).compress_type==zipfile.ZIP_DEFLATED
  for line in z.read('SHA256SUMS.txt').decode().splitlines():
   digest,name=line.split('  ',1);assert hashlib.sha256(z.read(name)).hexdigest()==digest
 ipk=next(out.glob('*.ipk')).read_bytes();members={}
 with tarfile.open(fileobj=io.BytesIO(ipk),mode='r:gz') as outer:
  for m in outer.getmembers():
   assert m.isfile();members[m.name.removeprefix('./')]=outer.extractfile(m).read()
 assert set(members)=={'debian-binary','control.tar.gz','data.tar.gz'} and members['debian-binary']==b'2.0\n'
 for name in ['control.tar.gz','data.tar.gz']:
  with tarfile.open(fileobj=io.BytesIO(members[name]),mode='r:gz') as t:
   names={m.name.removeprefix('./') for m in t.getmembers()}
   assert all(not m.issym() and not m.islnk() and '..' not in pathlib.PurePosixPath(m.name).parts and m.uid==m.gid==0 for m in t.getmembers())
   if name=='data.tar.gz':
    for required in ['usr/share/phone-panel/installed-update-manifest.json','etc/phone-dns/update-package.rb','etc/init.d/phone-panel-guard','etc/phone-dns/binding-registry.rb','etc/phone-dns/binding-manager.rb','etc/phone-dns/alignment.rb','etc/phone-dns/luci-cache.rb','etc/phone-dns/node-manager.rb','etc/phone-dns/device-operation.rb','usr/share/phone-panel/router/luci/resources/nodes.js','usr/lib/lua/luci/controller/phone_panel.lua','etc/config/phone_panel']:
     assert required in names,required
    assert not any('/node_modules/' in n or '/.git/' in n for n in names)
   else:
    assert {'control','preinst','postinst','prerm','conffiles'}<=names
    for script in ['preinst','postinst','prerm']:
     p=out/script;p.write_bytes(t.extractfile('./'+script).read());subprocess.run(['sh','-n',str(p)],check=True)
print('PASS: Windows-compatible ZIP, checksums, portable nested USTAR package, complete assets and maintainer syntax')
