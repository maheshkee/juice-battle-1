let selectedAddress = null
const API = ''  // empty = same origin, same port as the HTML page

async function scan() {
  const btn = document.getElementById('scan-btn')
  const status = document.getElementById('status')
  const list = document.getElementById('device-list')

  btn.disabled = true
  // show what URL we're on so we know the port
  status.textContent = 'Page URL: ' + window.location.href
  
  try {
    const res = await fetch(API + '/scan')
    const text = await res.text()
    status.textContent = 'Response: ' + text
  } catch (e) {
    status.textContent = 'Failed on: ' + API + '/scan  Error: ' + e.message
  }
  btn.disabled = false
}

function selectDevice(address) {
  selectedAddress = address
  document.getElementById('selected-address').textContent = address
  document.getElementById('detail-panel').classList.remove('hidden')
  document.getElementById('char-result').textContent = ''
}

async function readChar() {
  const uuid = document.getElementById('char-uuid').value.trim()
  if (!uuid) return
  const res = await fetch(API + '/read', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ address: selectedAddress, char_uuid: uuid })
  })
  const data = await res.json()
  document.getElementById('char-result').textContent =
    data.error ? 'Error: ' + data.error : 'Value (hex): ' + data.value
}

async function writeChar() {
  const uuid = document.getElementById('char-uuid').value.trim()
  const hex  = document.getElementById('write-data').value.trim()
  if (!uuid || !hex) return
  const res = await fetch(API + '/write', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ address: selectedAddress, char_uuid: uuid, data: hex })
  })
  const data = await res.json()
  document.getElementById('char-result').textContent =
    data.error ? 'Error: ' + data.error : 'Write successful'
}
