"""Arma la carpeta + zip del panel de ajuste para el equipo (Blender portátil, Pillow, tools/art y art/source).
Builds the team folder + zip of the tuning panel (portable Blender, Pillow, tools/art and art/source).
Uso / Usage: python empaquetar.py   (BLENDER_DIR = carpeta de Blender portátil, por defecto ~/tools/blender-5.2)"""
import datetime, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BLENDER_DIR = os.environ.get("BLENDER_DIR") or os.path.expanduser("~/tools/blender-5.2")
SALIDA = os.path.join(REPO, "art", "pruebas", "panel_equipo")
IGNORAR = shutil.ignore_patterns("__pycache__", "*.pyc")

BAT = r'''@echo off
setlocal
chcp 65001 >nul
set "RAIZ=%~dp0"
set "BLENDER=%RAIZ%blender\blender.exe"
set "PYEXE=%RAIZ%blender\5.2\python\bin\python.exe"
set "PYTHONPATH=%RAIZ%site-packages"
set "PYTHONUTF8=1"
if not exist "%BLENDER%" goto falta
if not exist "%PYEXE%" goto falta
if not exist "%RAIZ%tools\art\panel_ajuste\servidor.py" goto falta
if not exist "%RAIZ%art\source" goto falta
echo Abriendo el panel de ajuste. No cierres esta ventana negra mientras lo uses.
"%PYEXE%" "%RAIZ%tools\art\panel_ajuste\servidor.py"
if errorlevel 1 goto error
goto fin
:falta
echo Falta una parte del paquete (carpeta incompleta). Volve a descomprimir el zip entero en una carpeta nueva.
pause
goto fin
:error
echo El panel se cerro con un error. Mandanos una captura de esta ventana.
pause
:fin
endlocal
'''

LEEME = r'''PANEL DE AJUSTE - LEEME
1. Descomprimi el zip ENTERO en una carpeta (por ejemplo en el Escritorio). No lo abras desde dentro del zip.
2. Hace doble clic en ABRIR_PANEL.bat. No hace falta instalar nada.
3. Si Windows muestra "Windows protegio su PC" (SmartScreen): clic en "Mas informacion" y despues en "Ejecutar de todas formas".
4. Se abre el navegador solo. La primera vez tarda un minuto. No cierres la ventana negra mientras uses el panel.
5. Usalo con las instrucciones de arriba a la izquierda del panel (deslizadores, piezas, "Guardar").
6. "Guardar" escribe dentro de esta carpeta (en art\source), nunca en otro lado de tu compu.
7. Para mandarnos tus cambios: comprimi la carpeta art\source y mandanosla. Sirve tambien una captura de los numeros.
8. Para terminar, cerra la ventana negra.
9. Si algo falla, sale un cartel rojo en el panel o en la ventana negra: mandanos una captura.
10. El Blender incluido es de uso libre (licencia GPL en blender\license y blender\copyright.txt).
'''


def main():
    for p in ("blender.exe", os.path.join("5.2", "python", "bin", "python.exe")):
        if not os.path.exists(os.path.join(BLENDER_DIR, p)): sys.exit(f"Falta {p} en {BLENDER_DIR}")
    nombre = "panel_ajuste_" + datetime.date.today().isoformat()
    pkg = os.path.join(SALIDA, nombre)
    shutil.rmtree(pkg, ignore_errors=True); os.makedirs(pkg)
    print("Copiando Blender...", flush=True)
    shutil.copytree(BLENDER_DIR, os.path.join(pkg, "blender"), ignore=shutil.ignore_patterns("__pycache__", "*.pdb"))
    for lic in ("copyright.txt",):  # la licencia también va en la raíz / license also at the root
        shutil.copy2(os.path.join(BLENDER_DIR, lic), os.path.join(pkg, "LICENCIA_Blender.txt"))
    print("Copiando tools/art y art/source...", flush=True)
    shutil.copytree(os.path.join(REPO, "tools", "art"), os.path.join(pkg, "tools", "art"), ignore=IGNORAR)
    shutil.copytree(os.path.join(REPO, "art", "source"), os.path.join(pkg, "art", "source"), ignore=IGNORAR)
    py = os.path.join(pkg, "blender", "5.2", "python", "bin", "python.exe")
    print("Instalando Pillow...", flush=True)
    r = subprocess.run([py, "-m", "pip", "install", "--target", os.path.join(pkg, "site-packages"), "--no-compile",
                        "--only-binary=:all:", "Pillow"])
    if r.returncode: sys.exit("No se pudo bajar Pillow: copiar a mano la rueda cp313 win_amd64 a <paquete>/site-packages (pip install --target).")
    shutil.rmtree(os.path.join(pkg, "site-packages", "bin"), ignore_errors=True)
    with open(os.path.join(pkg, "ABRIR_PANEL.bat"), "w", encoding="utf-8", newline="\r\n") as f: f.write(BAT)
    with open(os.path.join(pkg, "LEEME.txt"), "w", encoding="utf-8", newline="\r\n") as f: f.write(LEEME)
    print("Comprimiendo...", flush=True)
    z = shutil.make_archive(pkg, "zip", SALIDA, nombre)
    print(z, round(os.path.getsize(z) / 1e6, 1), "MB")


if __name__ == "__main__":
    main()
