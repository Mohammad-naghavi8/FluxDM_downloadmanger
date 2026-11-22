const BRIDGE_BASE = 'http://127.0.0.1:45821';
const MENU_ID = 'send-to-download-manager';

const DIRECT_EXTENSIONS = new Set([
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'img',
  'exe', 'msi', 'msix', 'apk', 'dmg', 'deb', 'rpm', 'bin',
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'mp3', 'flac', 'wav', 'aac',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'
]);

function isSupportedDownloadUrl(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string') return false;
  try {
    const parsed = new URL(rawUrl);
    return parsed.protocol === 'http:' ||
      parsed.protocol === 'https:' ||
      parsed.protocol === 'ftp:';
  } catch {
    return false;
  }
}

function isLikelyDirectLink(rawUrl) {
  if (!isSupportedDownloadUrl(rawUrl)) return false;
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol === 'ftp:') return true;
    const lastSegment = parsed.pathname.split('/').pop() || '';
    const ext = lastSegment.includes('.')
      ? lastSegment.split('.').pop().toLowerCase()
      : '';
    return DIRECT_EXTENSIONS.has(ext) || /^part\d+$/.test(ext);
  } catch {
    return false;
  }
}

async function flashBadge(text, color) {
  try {
    await chrome.action.setBadgeBackgroundColor({ color });
    await chrome.action.setBadgeText({ text });
    await chrome.alarms.create('clear-badge', { delayInMinutes: 0.05 });
  } catch {
    // Ignore badge errors if action is unavailable
  }
}

async function sendToDesktopApp(url, fileName = '', autoStart = false) {
  const response = await fetch(`${BRIDGE_BASE}/add-download`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url, fileName, autoStart })
  });

  if (!response.ok) {
    throw new Error(`Desktop bridge returned HTTP ${response.status}`);
  }
  return response.json();
}

chrome.runtime.onInstalled.addListener(async () => {
  const { autoCapture } = await chrome.storage.local.get('autoCapture');
  if (typeof autoCapture !== 'boolean') {
    await chrome.storage.local.set({ autoCapture: true });
  }

  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: 'Download with Download Manager',
      contexts: ['link', 'audio', 'video', 'image']
    });
  });
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === 'clear-badge') {
    await chrome.action.setBadgeText({ text: '' });
  }
});

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== MENU_ID) return;
  const targetUrl = info.linkUrl || info.srcUrl || '';
  if (!isSupportedDownloadUrl(targetUrl)) {
    await flashBadge('ERR', '#E24A3B');
    return;
  }

  try {
    await sendToDesktopApp(targetUrl, '', false);
    await flashBadge('OK', '#00D58A');
  } catch {
    await flashBadge('OFF', '#FFC928');
  }
});

chrome.downloads.onCreated.addListener(async (downloadItem) => {
  const { autoCapture = true } = await chrome.storage.local.get('autoCapture');
  if (!autoCapture) return;

  const url = downloadItem.finalUrl || downloadItem.url;
  if (!isSupportedDownloadUrl(url)) return;
  if (url.startsWith('blob:') || url.startsWith('data:')) return;

  // Intercept direct links and standard browser downloads when desktop app is reachable
  try {
    const health = await fetch(`${BRIDGE_BASE}/health`);
    if (!health.ok) return;

    const shouldIntercept =
      isLikelyDirectLink(url) ||
      (downloadItem.fileSize && downloadItem.fileSize >= 512 * 1024) ||
      Boolean(downloadItem.mime && !downloadItem.mime.includes('text/html'));

    if (!shouldIntercept) return;

    await sendToDesktopApp(url, downloadItem.filename || '', false);
    await chrome.downloads.cancel(downloadItem.id);
    await chrome.downloads.erase({ id: downloadItem.id });
    await flashBadge('OK', '#00D58A');
  } catch {
    // Desktop app is not running — let the browser handle the download normally
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    if (message?.type === 'CHECK_HEALTH') {
      try {
        const res = await fetch(`${BRIDGE_BASE}/health`);
        sendResponse({ ok: res.ok });
      } catch {
        sendResponse({ ok: false });
      }
      return;
    }

    if (message?.type === 'SEND_URL') {
      const url = (message.url || '').trim();
      if (!isSupportedDownloadUrl(url)) {
        sendResponse({ ok: false, error: 'Unsupported URL (use HTTP, HTTPS, or FTP)' });
        return;
      }
      try {
        await sendToDesktopApp(url, '', false);
        await flashBadge('OK', '#00D58A');
        sendResponse({ ok: true });
      } catch (err) {
        sendResponse({ ok: false, error: 'Desktop Download Manager is not running' });
      }
    }
  })();

  return true;
});
