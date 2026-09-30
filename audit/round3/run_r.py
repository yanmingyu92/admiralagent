from pathlib import Path
import subprocess, os, sys
root=Path.cwd()
r='C:/Users/JaimeYan/AppData/Local/Programs/R/R-4.6.0/bin/Rscript.exe'
env=os.environ.copy()
for k in ['LC_ALL','LC_CTYPE','LANG']: env[k]='English_United States.utf8'
env['PATH']='C:/Users/JaimeYan/AppData/Local/Pandoc;'+env['PATH']
env['RSTUDIO_PANDOC']='C:/Users/JaimeYan/AppData/Local/Pandoc'
with open(sys.argv[1],'wb') as log:
 p=subprocess.run([r,*sys.argv[2:]],stdout=log,stderr=subprocess.STDOUT,env=env)
print('R exit:',p.returncode)
sys.exit(p.returncode)