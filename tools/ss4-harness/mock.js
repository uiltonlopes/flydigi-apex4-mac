// Local test harness: fakes the Electron bridge so the SS4 renderer shows an Apex 4 (deviceType 84).
(function(){
  const recv = {}; window.__recv = recv; window.__log = [];
  const fire = (ch, ...args) => { (recv[ch]||[]).slice().forEach(fn => { try { fn({}, ...args) } catch(e) { console.error('handler', ch, e) } }) };
  window.__fire = fire;
  window.platform = 'win32';
  window.__dev = {productName:'APEX 4', category:1, connectType:1, deviceCode:'k2', deviceType:84, deviceMac:'f2:5a:90:54', uid:'k2-84-f25a9054', isConnected:true, battery:80, firmwareVersion:'6.8.3.0', vendorId:1118, productId:654, isNewArchitecture:false, nickname:'', firmwares:[{chipModule:0,chipType:0,version:'6.8.3.0'},{chipModule:5,chipType:0,version:'1.0.6'},{chipModule:4,chipType:0,version:'1.0.3'}]};
  window.__detail = {parent: window.__dev, firmwares:{trigger:'1.0.6',adc:'1.0.2',screen:'1.0.3',dongle:'',si:'',rf:''}, supportAdaptTrigger:true, supportScreen:true, supportLed:true, supportNs:true, supportTriggerVibration:true, containKeys:[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,24,27,240,241]};
  window.__configs = null; // set later to feed GetConfig replies
  window.api = new Proxy({}, {get:(t,k)=>{
    if (k==='getAppVersion') return async()=>'4.2.2.3';
    if (k==='getCurrentChangelog') return async()=>'';
    if (k==='getLatestReleases') return async()=>[];
    if (k==='isFrameless'||k==='isFullscreen'||k==='isMaximized'||k==='isMinimized') return async()=>false;
    if (k==='getGpuAccelerationEnabled') return async()=>true;
    if (k==='pathExists') return async()=>false;
    if (k==='checkDiskSpace') return async()=>({free:1e12});
    if (k==='getShellPath') return async()=>'C:/Users/x';
    if (k==='clipboardReadText') return async()=>'';
    if (String(k).startsWith('handle')) return ()=>()=>{};
    return ()=>{};
  }});
  window.electronAPI = {getDynamicImageSources:(a,b,c,d)=>`/assets/images/product/${a}/${b}/${c}/${d}`};
  window.ipcSocket = {
    send(ch, msg){ window.__log.push([ch, msg]);
      if (ch==='check_service_process') { setTimeout(()=>fire('show_service_alert', {isInstalled:true,isRunning:true}), 50); return; }
      if (ch!=='send_command'||!msg) return;
      switch(msg.cmdId){
        case 1: setTimeout(()=>fire('initResult', {LogEnabled:false, dataPath:'C:/ss4/'}), 50); break;
        case 4097: setTimeout(()=>fire('receiveEquipmentHallListSocket',[window.__dev]), 50); break;
        case 4099: setTimeout(()=>fire('receiveDeviceDetail', window.__detail, !!msg.onlyRefresh), 50); break;
        case 4100: setTimeout(()=>fire('refreshConfigCurrentUsed', 0), 50); break;
        case 4112: if (window.__onGetConfig) window.__onGetConfig(msg); break;
        default: if (window.__onCmd) window.__onCmd(msg);
      }
    },
    receive(ch, fn){ (recv[ch]=recv[ch]||[]).push(fn); return ()=>{ recv[ch]=(recv[ch]||[]).filter(f=>f!==fn) } },
    once(ch, fn){ const w=(...a)=>{ recv[ch]=(recv[ch]||[]).filter(f=>f!==w); fn(...a) }; (recv[ch]=recv[ch]||[]).push(w) },
    removeAllListeners(ch){ delete recv[ch] }
  };
})();
// GetConfig (4112) replies: msg.configType is an array of ConfigType (1 Simple,2 Led,3 Button,4 Macro,5 Joystick,6 Motion,7 Trigger,8 Vibration)
window.__onGetConfig = function(msg){
  const fire = window.__fire, types = msg.configType || [0];
  const keys = window.__detail.containKeys.filter(k => k < 240);
  const has = t => types.includes(0) || types.includes(t);
  setTimeout(() => {
    if (has(1)) fire('getSimpleConfigs', keys.map(k => ({keyId:k, mapType:0, mapKeyId:k, mapKeyboardKeyId:0})));
    if (has(2)) fire('getConfigLedResult', {currentConfig:{mode:1, period:50, brightness:60, useColorCount:3, proto:1, syncWithGripEnable:false, colors:[{r:40,g:90,b:250},{r:250,g:60,b:60},{r:60,g:250,b:90}]}});
    if (has(8)) fire('getConfigVibrationResult', {enable:true, min:0, max:100, scale:50});
    if (has(3) && msg.keyId !== undefined) fire('getConfigKeyResult', {keyId:msg.keyId, mapType:0, mapTypeKey:{mapControllerKeyId:msg.keyId, mapKeyboardKeyId:0}});
    if (has(5)) fire('getConfigJoystickResult', {leftJoystickParam:{mapType:0, mapTypeJoystick:{deadZone:5, curveType:0, point1:{x:40,y:40}, point2:{x:80,y:80}, sensitivity:50}, end:100}, rightJoystickParam:{mapType:0, mapTypeJoystick:{deadZone:5, curveType:0, point1:{x:40,y:40}, point2:{x:80,y:80}, sensitivity:50}, end:100}});
    if (has(6)) fire('getConfigMotionResult', {useMode:0, mappingType:0, mappingTypeJoystick:{enableKey:12, enableType:0, deadZone:5, sensitivity:50}, mappingTypeMouse:{enableKey:12, enableType:0, sensitivityX:50, sensitivityY:50}});
    if (has(7)) fire('getConfigTriggerResult', {leftTriggerConfig:{zero:0, end:100, type:0, point1:{x:40,y:40}, point2:{x:80,y:80}, triggerVibrationConfigBean:{enable:false}, triggerAdapterConfigBean:{type:0}}, rightTriggerConfig:{zero:0, end:100, type:0, point1:{x:40,y:40}, point2:{x:80,y:80}, triggerVibrationConfigBean:{enable:false}, triggerAdapterConfigBean:{type:0}}});
  }, 50);
};
