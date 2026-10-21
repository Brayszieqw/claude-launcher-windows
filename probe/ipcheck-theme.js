(() => {
  if (location.origin !== 'https://ipcheck.ing' || window.top !== window) return;
  const apply = () => {
    const style = document.createElement('style');
    style.id = 'claude-launcher-theme';
    style.textContent = `
      :root, .dark {
        color-scheme: dark !important;
        --background: #2b1f1a !important;
        --foreground: #fff1db !important;
        --card: rgb(49 34 26 / 88%) !important;
        --card-foreground: #fff1db !important;
        --popover: #39271e !important;
        --popover-foreground: #fff1db !important;
        --primary: #f1c296 !important;
        --primary-foreground: #2b1f1a !important;
        --secondary: #4a3326 !important;
        --secondary-foreground: #fff1db !important;
        --muted: rgb(87 59 42 / 55%) !important;
        --muted-foreground: #cdb39b !important;
        --accent: #60412d !important;
        --accent-foreground: #fff1db !important;
        --action: #e3ae83 !important;
        --action-foreground: #2b1f1a !important;
        --info: #8ad0e9 !important;
        --info-foreground: #2b1f1a !important;
        --success: #87d09c !important;
        --success-foreground: #2b1f1a !important;
        --warning: #ffd89a !important;
        --warning-foreground: #2b1f1a !important;
        --destructive: #ffaaa0 !important;
        --destructive-foreground: #2b1f1a !important;
        --border: rgb(233 198 160 / 25%) !important;
        --input: rgb(233 198 160 / 30%) !important;
        --ring: #f1c296 !important;
        --page-bg: transparent !important;
      }
      html {
        background: #2b1f1a !important;
      }
      body {
        font-family: 'Microsoft YaHei UI', 'Microsoft YaHei', sans-serif;
        color: var(--foreground) !important;
        background: linear-gradient(110deg, rgb(27 18 14 / 70%), rgb(43 31 26 / 45%)),
          url('https://claude-assets.local/background.png') center / cover fixed !important;
        min-height: 100vh;
      }
      [data-slot="card"] { backdrop-filter: blur(14px); }
      ::selection { background: #e3ae83; color: #2b1f1a; }
    `;
    document.head.appendChild(style);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply, { once: true });
  else apply();
})();
