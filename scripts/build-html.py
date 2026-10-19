"""Bundle local runtime, CSS and verified audio into the native launcher's HTML."""
from pathlib import Path
import base64,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'assets/upstream.lock.json').read_text())
assets={}
for name,item in lock['assets'].items():
    data=(ROOT/item['path']).read_bytes()
    if hashlib.sha256(data).hexdigest()!=item['sha256']:
        raise RuntimeError(f'SHA-256 mismatch: {name}')
    assets[Path(name).stem]='data:audio/mpeg;base64,'+base64.b64encode(data).decode()
runtime=(ROOT/'lib/splash.js').read_text()
html=(ROOT/'web/index.html').read_text()
html=html.replace('<link rel="stylesheet" href="../lib/splash.css">','<style>'+(ROOT/'lib/splash.css').read_text()+'</style>')
bootstrap='window.__CODEX_STARTUP_ASSETS__ = '+json.dumps(assets)+';\nwindow.__DSH_STARTUP_SCRIPT_URL__ = URL.createObjectURL(new Blob(['+json.dumps(runtime,ensure_ascii=False)+'], {type:"text/javascript"}));\n'
html=html.replace('<script defer src="../lib/splash.js"></script>','<script>'+bootstrap+runtime+'</script>')
out=Path(sys.argv[1]);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(html)
