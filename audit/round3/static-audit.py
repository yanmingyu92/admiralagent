from pathlib import Path
import re,json,hashlib
root=Path('admiralagent'); out=root/'audit/round3'
rows=[]; enc=[]; branches=[]
for p in sorted((root/'R').glob('*.R')):
 raw=p.read_bytes(); s=raw.decode('utf-8'); enc.append(dict(file=str(p),utf8=True,crlf=raw.count(b'\r\n'),lf=raw.count(b'\n'),sha256=hashlib.sha256(raw).hexdigest()))
 for m in re.finditer(r"((?:#'[^\n]*\n)+)(\w+)\s*<-\s*function\s*\((.*?)\)\s*\{",s,re.S):
  docs,name,args=m.groups()
  if '@export' not in docs: continue
  # Actual formal names are checked by the R/Rd probe; preserve roxygen declarations here.
  rows.append(dict(fn=name,file=str(p),params=re.findall(r'@param\s+(\w+)',docs)))
 for i,line in enumerate(s.splitlines(),1):
  if re.search(r'\bstop\(|\breturn\("|problems <-|bad <-',line): branches.append(dict(file=str(p),line=i,code=line.strip()))
for p in sorted((root/'tests/testthat').glob('*.R')):
 raw=p.read_bytes();raw.decode('utf-8');enc.append(dict(file=str(p),utf8=True,crlf=raw.count(b'\r\n'),lf=raw.count(b'\n'),sha256=hashlib.sha256(raw).hexdigest()))
(out/'roxygen-params.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
(out/'encoding.json').write_text(json.dumps(enc,indent=2),encoding='utf-8')
(out/'error-branches.json').write_text(json.dumps(branches,indent=2),encoding='utf-8')
print('UTF-8 files',len(enc),'documented exports',len(rows),'error/check branches',len(branches))