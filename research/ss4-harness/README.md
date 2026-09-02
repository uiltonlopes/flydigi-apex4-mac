# Space Station 4 renderer harness

Runs the *official* SS4 front-end (Electron renderer bundle) in a plain browser with a fake Apex 4
connected, so its screens can be studied pixel by pixel without Windows. Only `mock.js` is ours;
the renderer itself is Flydigi's and is **not** in this repo.

1. Unpack `app.asar` from the SS4 installer (Inno 6.7 needs the patched `innoextract`, see
   `docs/spacestation4-analysis.md`) and locate `.vite/renderer/main_window/`.
2. Copy `mock.js` next to `index.html`, and create `mock.html` = `index.html` with
   `<script src="/mock.js"></script>` inserted right after `<title>`.
3. `python3 -m http.server 8765 --directory <main_window>` and open `http://localhost:8765/mock.html`.
4. Click the APEX 4 card. Tabs are antd: `document.querySelectorAll('.ant-tabs-tab')[n].click()`.

`mock.js` fakes `window.api`, `window.ipcSocket` (the IPC bridge: `send_command` with `cmdId`, replies
on named channels such as `receiveEquipmentHallListSocket`, `receiveDeviceDetail`, `getSimpleConfigs`,
`getConfigLedResult`) and `window.electronAPI`. Command ids and reply channel names are listed in
`docs/spacestation4-analysis.md`.
