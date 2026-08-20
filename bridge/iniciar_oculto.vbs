' ════════════════════════════════════════════════════════════
' FENLORA · Arranque automático del Print Bridge (ventana oculta)
' Corre "node bridge.js" en segundo plano, sin ventana negra.
' Debe quedar en la MISMA carpeta que bridge.js.
' Para que arranque solo al prender el PC: pon un ACCESO DIRECTO
' de este archivo en la carpeta de Inicio (Win+R -> shell:startup).
' ════════════════════════════════════════════════════════════
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
carpeta = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = carpeta
' FENLORA_IMPRESORA = nombre con el que compartiste la impresora en Windows (estándar: POS58)
sh.Run "cmd /c set FENLORA_IMPRESORA=POS58 && node bridge.js", 0, False
