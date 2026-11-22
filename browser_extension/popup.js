const statusBadge = document.getElementById('statusBadge');
const autoCaptureToggle = document.getElementById('autoCaptureToggle');
const urlInput = document.getElementById('urlInput');
const sendBtn = document.getElementById('sendBtn');
const feedback = document.getElementById('feedback');

async function init() {
  const { autoCapture = true } = await chrome.storage.local.get('autoCapture');
  autoCaptureToggle.checked = autoCapture;

  const health = await chrome.runtime.sendMessage({ type: 'CHECK_HEALTH' });
  if (health?.ok) {
    statusBadge.textContent = 'Connected';
    statusBadge.classList.add('online');
  } else {
    statusBadge.textContent = 'Offline';
  }
}

autoCaptureToggle.addEventListener('change', async () => {
  await chrome.storage.local.set({ autoCapture: autoCaptureToggle.checked });
});

sendBtn.addEventListener('click', async () => {
  const url = urlInput.value.trim();
  if (!url) {
    feedback.textContent = 'Enter a download URL first.';
    return;
  }

  feedback.textContent = 'Sending...';
  const result = await chrome.runtime.sendMessage({ type: 'SEND_URL', url });
  if (result?.ok) {
    feedback.textContent = 'Sent to Download Manager!';
    urlInput.value = '';
  } else {
    feedback.textContent = result?.error || 'Could not reach desktop app.';
  }
});

init();
