# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

# Bleak imports a number of WinRT projection modules dynamically.  PyInstaller
# cannot reliably infer them, so keep both broad collection and an explicit
# safety list for the modules used by Bleak's Windows scanner/client backend.
hiddenimports = collect_submodules('bleak') + collect_submodules('winrt')
hiddenimports += ['winrt.windows.devices.bluetooth', 'winrt.windows.devices.bluetooth.advertisement', 'winrt.windows.devices.bluetooth.genericattributeprofile', 'winrt.windows.devices.enumeration', 'winrt.windows.foundation', 'winrt.windows.foundation.collections', 'winrt.windows.storage.streams']

datas = collect_data_files('bleak')

a = Analysis(
    ['app.py'],
    pathex=['.'],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='HUDWAY_BLE_Tester_Diagnostic',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
