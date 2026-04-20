var eventCount=0;
function connectSSE(){
  var src=new EventSource('/events');
  src.onmessage=function(e){handleEvent(JSON.parse(e.data));};
  src.onerror=function(){setTimeout(connectSSE,3000);};
}
function handleEvent(ev){
  if(ev.type==='snapshot'){applySnapshot(ev);return;}
  if(ev.type==='ble')updateBLE(ev.connected,ev.device);
  if(ev.type==='led')updateLED(ev.state);
  appendLog(ev);
}
function applySnapshot(snap){
  updateBLE(snap.ble_connected,snap.ble_device);
  updateLED(snap.led_on);
  if(snap.events){snap.events.forEach(function(ev){appendLog(ev,true);});updateCount();}
}
function updateBLE(connected,device){
  var dot=document.getElementById('ble-dot');
  var text=document.getElementById('ble-text');
  var dev=document.getElementById('ble-device');
  var card=document.getElementById('card-ble');
  if(connected){
    dot.className='dot active';text.textContent='Connected';
    dev.textContent=device||'';card.style.borderTopColor='#4fcca3';
  }else{
    dot.className='dot';text.textContent='Waiting for connection...';
    dev.textContent='';card.style.borderTopColor='#1a2438';
  }
}
function updateLED(state){
  var dot=document.getElementById('led-dot');
  var text=document.getElementById('led-text');
  var card=document.getElementById('card-led');
  if(state){dot.className='dot green on';text.textContent='ON';card.style.borderTopColor='#4fcc60';}
  else{dot.className='dot green';text.textContent='OFF';card.style.borderTopColor='#1a2438';}
}
function appendLog(ev,initial){
  var logEl=document.getElementById('log');
  var entry=document.createElement('div');
  entry.className='log-entry';
  var typeClass='type-'+(ev.type||'system');
  var desc=ev.desc||(ev.type==='led'?('LED '+(ev.state?'ON':'OFF')+' via '+ev.source):JSON.stringify(ev));
  entry.innerHTML='<span class="log-ts">'+(ev.ts||'')+'</span>'+
    '<span class="log-type '+typeClass+'">'+ev.type+'</span>'+
    '<span class="log-desc">'+desc+'</span>';
  if(initial){logEl.appendChild(entry);}else{logEl.insertBefore(entry,logEl.firstChild);}
  eventCount++;updateCount();
}
function updateCount(){document.getElementById('event-count').textContent=eventCount+' events';}
window.onload=connectSSE;