const notice = document.getElementById('device-note');
if (!/Macintosh|MacIntel/.test(navigator.userAgent) || navigator.maxTouchPoints > 1) notice.hidden = false;

for (const button of document.querySelectorAll('[data-copy]')) {
  button.addEventListener('click', async () => {
    const command = document.getElementById(button.dataset.copy).textContent;
    try {
      await navigator.clipboard.writeText(command);
      button.textContent = '已复制 ✓';
      document.getElementById('copy-status').textContent = '命令已复制，请粘贴到终端并按回车。';
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(document.getElementById(button.dataset.copy));
      selection.removeAllRanges(); selection.addRange(range);
      button.textContent = '请按 ⌘C 复制';
      document.getElementById('copy-status').textContent = '已选中命令，请按 Command C 手动复制。';
    }
  });
}

for (const video of document.querySelectorAll('video')) {
  video.addEventListener('play', () => {
    for (const other of document.querySelectorAll('video')) if (other !== video) other.pause();
  });
}
