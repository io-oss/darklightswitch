// Chromium 系（Electron）内核「系统明暗」探针。
//
// 用途：验证 darklight-toggle 切换后，Electron 的 nativeTheme.shouldUseDarkColors
// 是否与系统实际明暗一致。Linux 上这个值来自 Chromium 对系统主题的读取，
// 与 Electron 应用（VS Code / Trae / DSH Desktop 等）的界面深浅直接相关。
//
// 输出（每行带毫秒时间戳）：
//   READY  启动完成
//   STATE  主进程当前判定的明暗（每 500ms 一次，便于运行器取最后状态）
//   EVENT  nativeTheme 的 updated 事件
//   RENDER renderer 里 prefers-color-scheme 的变化（网页内容的取值路径）
const { app, BrowserWindow, nativeTheme } = require('electron')

const startedAt = Date.now()
const log = (line) => process.stdout.write(`${Date.now() - startedAt} ${line}\n`)

// 与真实应用一致：跟随系统，而不是强制某个值。
nativeTheme.themeSource = 'system'

const state = () => (nativeTheme.shouldUseDarkColors ? 'dark' : 'light')

const html = `<html><body><script>
  const mq = matchMedia('(prefers-color-scheme: dark)');
  const report = () => console.log('RENDERER ' + (mq.matches ? 'dark' : 'light'));
  report();
  mq.addEventListener('change', report);
</script></body></html>`

app.whenReady().then(() => {
  log(`READY electron=${process.versions.electron} chrome=${process.versions.chrome}`)
  log(`STATE ${state()}`)
  nativeTheme.on('updated', () => log(`EVENT ${state()}`))
  setInterval(() => log(`STATE ${state()}`), 500)

  const win = new BrowserWindow({
    width: 320,
    height: 140,
    show: false,
    webPreferences: { backgroundThrottling: false },
  })
  win.webContents.on('console-message', (...args) => {
    const event = args[0]
    const message = event && typeof event === 'object' && 'message' in event ? event.message : args[2]
    if (typeof message === 'string' && message.startsWith('RENDERER ')) {
      log(`RENDER ${message.slice('RENDERER '.length)}`)
    }
  })
  win.loadURL('data:text/html,' + encodeURIComponent(html))
})
