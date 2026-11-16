# Blender sin interfaz que queda abierto: lee por stdin la ruta de un trabajo de rig3d_blender.py, lo corre y avisa.
# Windowless Blender that stays open: reads a rig3d_blender.py job path from stdin, runs it and reports.
#   blender -b --factory-startup -P worker_blender.py
# PERSIST_PANEL conserva la escena armada entre trabajos (esqueleto, partes sin cambios); si un trabajo falla se vacía
# PERSIST_PANEL keeps the built scene between jobs (skeleton, unchanged parts); it is emptied if a job fails
import os, sys, traceback

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rig3d_blender.py")
sys.path.insert(0, os.path.dirname(SCRIPT))  # rig3d_partes
CODIGO = compile(open(SCRIPT, encoding="utf-8").read(), SCRIPT, "exec")
PERSIST_PANEL = {}

print("@@LISTO", flush=True)
for linea in sys.stdin:
    trabajo = linea.strip()
    if not trabajo: continue
    sys.argv = ["blender", "--", trabajo]
    try:
        exec(CODIGO, {"__name__": "__main__", "__file__": SCRIPT, "PERSIST_PANEL": PERSIST_PANEL})
        print("@@FIN ok", flush=True)
    except BaseException:
        PERSIST_PANEL.clear()
        print("@@FIN error " + traceback.format_exc()[-1500:].replace("\n", " | "), flush=True)
