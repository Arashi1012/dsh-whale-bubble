/**
 * dsh-whale-bubble — Host half.
 *
 * Tracks the live progress of the most recently active *root* session from the
 * committed session log, exposes it on a loopback HTTP endpoint, and keeps a
 * native always-on-top whale window (whale-bubble.ps1, WPF) alive on the
 * desktop. The window polls `/state`, so the bubble keeps working while the
 * Harness window is minimized.
 *
 * No dependencies: plain Node ESM so an installed bundle loads as-is.
 */
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, appendFileSync, statSync, readFileSync, renameSync } from 'node:fs'
import { createServer } from 'node:http'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const VERSION = '0.1.0'
const HERE = dirname(fileURLToPath(import.meta.url))
const BUBBLE_SCRIPT = join(HERE, 'whale-bubble.ps1')
const DATA_DIR = join(process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local'), 'dsh-whale-bubble')
const LOG_FILE = join(DATA_DIR, 'plugin.log')
const MAX_LOG_BYTES = 512 * 1024

const TOOL_LABELS = {
  pwsh: '执行命令',
  bash: '执行命令',
  read: '读取文件',
  write: '写入文件',
  edit: '修改文件',
  glob: '查找文件',
  grep: '搜索内容',
  web_search: '联网搜索',
  web_fetch: '抓取网页',
  ask_user_question: '等待你回答',
  todo_write: '更新任务清单',
  subagent: '派发子任务',
  subagent_fork: '派发子任务',
  send_message: '给队友发消息',
  wait_agent: '等待队友',
  list_agents: '查看队友',
  plugin_manager: '管理插件',
  cordis_inspect_query: '查询接口',
  cordis_inspect_list: '查询接口',
  workflow: '编排子任务',
  present: '交付文件',
  skill: '加载技能',
  job_output: '读取后台任务',
  job_list: '查看后台任务',
  job_kill: '结束后台任务',
  team_task_create: '创建团队任务',
  team_task_update: '更新团队任务',
  team_task_list: '查看团队任务',
  team_task_get: '查看团队任务',
  interrupt_agent: '中断队友',
  spawn_teammate: '创建队友',
}

/** Keep one log line readable on the bubble's single line. */
function shortText(value, max = 46) {
  const text = String(value).replace(/\s+/g, ' ').trim()
  if (text.length <= max) return text
  return `${text.slice(0, Math.max(1, max - 1))}…`
}

/** Pull the most human-meaningful argument out of a tool call. */
function summarizeArguments(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') return ''
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return shortText(raw, 40)
  }
  if (value === null || typeof value !== 'object') return shortText(raw, 40)
  const preferred = [
    'command', 'file_path', 'path', 'pattern', 'query', 'url',
    'description', 'prompt', 'text', 'title', 'name', 'target', 'session_id',
  ]
  for (const key of preferred) {
    const candidate = value[key]
    if (typeof candidate === 'string' && candidate.trim() !== '') return shortText(candidate)
  }
  for (const candidate of Object.values(value)) {
    if (typeof candidate === 'string' && candidate.trim() !== '') return shortText(candidate)
  }
  return ''
}

function formatDuration(ms) {
  const total = Math.max(0, Math.round((Number(ms) || 0) / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60)
    return `${hours}:${String(minutes % 60).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  }
  return minutes > 0 ? `${minutes}:${String(seconds).padStart(2, '0')}` : `${seconds}s`
}

const MENU_LABELS = {
  reset: '回到右下角',
  test: '试一下完成提醒',
  exit: '退出气泡',
}

/** Map a finished turn into the hover card. */
function completionView(completion) {
  const reason = completion?.reason ?? 'completed'
  const duration = formatDuration(completion?.durationMs ?? 0)
  const steps = completion?.steps ?? 0
  const meta = `用时 ${duration} · ${steps} 步`
  if (reason === 'completed') {
    return { kind: 'done', tone: 'green', title: '任务完成', meta, detail: '', bar: false }
  }
  if (reason === 'error' || reason === 'max-tokens') {
    return { kind: 'error', tone: 'orange', title: '任务出错', meta, detail: '', bar: false }
  }
  return { kind: 'done', tone: 'gray', title: '任务已停止', meta, detail: '', bar: false }
}

function ensureDataDir() {
  try {
    mkdirSync(DATA_DIR, { recursive: true })
  } catch {
    /* ignore */
  }
}

function log(line) {
  ensureDataDir()
  try {
    if (existsSync(LOG_FILE) && statSync(LOG_FILE).size > MAX_LOG_BYTES) {
      renameSync(LOG_FILE, `${LOG_FILE}.old`)
    }
    appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${line}\n`)
  } catch {
    /* ignore */
  }
}

function readLogTail() {
  try {
    if (!existsSync(LOG_FILE)) return ''
    const text = readFileSync(LOG_FILE, 'utf8')
    return text.slice(-24000)
  } catch {
    return ''
  }
}

/** Host plugin entry point. */
export function apply(ctx, config) {
  const options = {
    port: 43980,
    sound: true,
    ...(config && typeof config === 'object' ? config : {}),
  }

  const tracks = new Map()
  let displaySessionId = null
  let completion = null
  let hello = null
  let demoUntil = 0
  let demoPayload = null
  let captureSeq = 0
  let captureDone = 0
  let shuttingDown = false
  let disposed = false
  let userQuit = false
  let serviced = false
  let server = null
  let actualPort = Number(options.port) || 43980
  let child = null
  let childPid = 0
  let restarts = 0
  let spawnTimer = null

  ensureDataDir()

  function trackOf(sessionId) {
    let track = tracks.get(sessionId)
    if (track === undefined) {
      track = { running: false, turn: 0, step: 0, tool: '', detail: '', startedAt: 0, lastAt: 0 }
      tracks.set(sessionId, track)
    }
    return track
  }

  function onSessionEvent(session, event) {
    if (disposed) return
    if (session?.header?.parentSession) return // subagent turns are not the user's task
    const sessionId = String(session.id)
    const data = event?.data ?? {}
    const at = typeof event?.time === 'number' ? event.time : Date.now()
    const track = trackOf(sessionId)
    track.lastAt = at

    switch (event?.type) {
      case 'turn/start':
        track.turn = typeof data.turn === 'number' ? data.turn : 0
        track.startedAt = at
        track.step = 0
        track.tool = ''
        track.detail = ''
        track.running = true
        displaySessionId = sessionId
        break
      case 'tool/call':
        track.running = true
        if (!track.startedAt) track.startedAt = at
        track.step += 1
        track.tool = typeof data.name === 'string' ? data.name : ''
        track.detail = summarizeArguments(data.arguments)
        displaySessionId = sessionId
        break
      case 'assistant/message':
        track.running = true
        if (!track.startedAt) track.startedAt = at
        displaySessionId = sessionId
        break
      case 'turn/end': {
        track.running = false
        const reason = data?.reason?.kind ?? 'completed'
        completion = {
          at,
          reason,
          durationMs: Math.max(0, at - (track.startedAt || at)),
          steps: track.step,
          turn: track.turn,
          sessionId,
        }
        displaySessionId = sessionId
        break
      }
      default:
        break
    }
  }

  function snapshot() {
    const now = Date.now()
    let running = null
    let runningCount = 0
    for (const [sessionId, track] of tracks) {
      if (!track.running) continue
      runningCount += 1
      if (running === null || track.startedAt > running.startedAt) running = { sessionId, ...track }
    }
    const shown = running ?? (displaySessionId !== null ? tracks.get(displaySessionId) ?? null : null)
    const shownId = running?.sessionId ?? displaySessionId
    const realCompletion = completion !== null && now - completion.at < 180000 ? completion : null
    const demoActive = demoUntil > now && demoPayload !== null
    const latest = demoActive ? demoPayload : realCompletion
    const elapsedOfRunning = running !== null
      ? Math.min(Math.max(0, now - (running.startedAt || now)), 24 * 3600 * 1000)
      : 0

    let view
    if (demoActive) {
      view = completionView(demoPayload)
    } else if (running !== null) {
      const label = TOOL_LABELS[running.tool] ?? running.tool
      const elapsed = formatDuration(elapsedOfRunning)
      const title = running.step > 0 ? (label || '工作中') : '思考中'
      view = {
        kind: 'working',
        tone: 'blue',
        title,
        meta: running.step > 0 ? `第 ${running.step} 步 · ${elapsed}` : elapsed,
        detail: running.detail || '',
        bar: running.step > 0,
      }
    } else if (latest !== null && now - latest.at < 15000) {
      view = completionView(latest)
    } else {
      view = { kind: 'idle', tone: 'blue', title: '', meta: '', detail: '', bar: false }
    }

    return {
      ok: true,
      version: VERSION,
      now,
      working: running !== null,
      runningSessions: runningCount,
      sessionId: shownId,
      turn: shown?.turn ?? 0,
      step: shown?.step ?? 0,
      tool: shown?.tool ?? '',
      toolLabel: TOOL_LABELS[shown?.tool ?? ''] ?? shown?.tool ?? '',
      detail: shown?.detail ?? '',
      elapsedMs: elapsedOfRunning,
      completion: latest,
      view,
      menu: MENU_LABELS,
      demo: {
        kind: 'done',
        tone: 'green',
        title: '任务完成',
        meta: `用时 ${formatDuration(201000)} · 12 步`,
        detail: '',
        bar: false,
      },
      sound: options.sound !== false,
      shutdown: shuttingDown,
      captureSeq,
      helloAt: hello?.at ?? 0,
    }
  }

  function json(response, status, body) {
    const payload = JSON.stringify(body)
    response.writeHead(status, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'content-length': Buffer.byteLength(payload),
    })
    response.end(payload)
  }

  function text(response, status, body) {
    response.writeHead(status, {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
    })
    response.end(body)
  }

  function onRequest(request, response) {
    let path
    try {
      path = new URL(request.url ?? '/', `http://127.0.0.1:${actualPort}`).pathname
    } catch {
      text(response, 400, 'bad request')
      return
    }

    if (path === '/state') {
      json(response, 200, snapshot())
      return
    }
    if (path === '/health') {
      json(response, 200, { ok: true, version: VERSION, port: actualPort })
      return
    }
    if (path === '/log') {
      text(response, 200, readLogTail())
      return
    }
    if (path === '/screenshot') {
      captureSeq += 1
      json(response, 200, { ok: true, seq: captureSeq })
      return
    }
    if (path === '/demo') {      const at = Date.now()
      demoUntil = at + 12000
      demoPayload = { at, reason: 'completed', durationMs: 201000, steps: 12, turn: 0, sessionId: 'demo' }
      json(response, 200, { ok: true })
      return
    }
    if (path === '/quit' && request.method === 'POST') {
      userQuit = true
      log('bubble quit requested by the user; not restarting it in this activation')
      json(response, 200, { ok: true })
      return
    }
    if (path === '/hello' && request.method === 'POST') {
      let body = ''
      request.on('data', (chunk) => {
        body += chunk
        if (body.length > 8192) request.destroy()
      })
      request.on('end', () => {
        try {
          const parsed = JSON.parse(body)
          hello = {
            at: Date.now(),
            pid: Number(parsed?.pid) || 0,
            hwnd: String(parsed?.hwnd ?? ''),
            width: Number(parsed?.width) || 0,
            height: Number(parsed?.height) || 0,
          }
          serviced = true
          restarts = 0
          log(`bubble hello pid=${hello.pid} hwnd=${hello.hwnd} ${hello.width}x${hello.height}`)
        } catch {
          hello = { at: Date.now(), pid: 0, hwnd: '' }
        }
        json(response, 200, { ok: true })
      })
      return
    }
    if (path === '/capture-done' && request.method === 'POST') {
      let body = ''
      request.on('data', (chunk) => {
        body += chunk
        if (body.length > 8192) request.destroy()
      })
      request.on('end', () => {
        try {
          captureDone = Number(JSON.parse(body)?.seq) || captureDone
        } catch {
          /* ignore */
        }
        json(response, 200, { ok: true })
      })
      return
    }
    json(response, 404, { ok: false, error: 'not found' })
  }

  function listen(port, remaining) {
    const candidate = createServer(onRequest)
    candidate.once('error', (error) => {
      if (error?.code === 'EADDRINUSE' && remaining > 0) {
        try {
          candidate.close()
        } catch {
          /* ignore */
        }
        listen(port + 1, remaining - 1)
        return
      }
      log(`state server failed: ${error?.message ?? error}`)
    })
    candidate.listen(port, '127.0.0.1', () => {
      server = candidate
      actualPort = port
      log(`state server listening on 127.0.0.1:${port}`)
      startBubble()
    })
  }

  function startBubble() {
    if (disposed) return
    if (!existsSync(BUBBLE_SCRIPT)) {
      log(`bubble script missing: ${BUBBLE_SCRIPT}`)
      return
    }
    if (child !== null) return
    const startedAt = Date.now()
    try {
      child = spawn(
        'powershell.exe',
        [
          '-NoProfile',
          '-STA',
          '-ExecutionPolicy', 'Bypass',
          '-WindowStyle', 'Hidden',
          '-File', BUBBLE_SCRIPT,
          '-Port', String(actualPort),
        ],
        { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
      )
    } catch (error) {
      log(`bubble spawn threw: ${error?.message ?? error}`)
      child = null
      return
    }
    log(`bubble spawned pid=${child.pid} port=${actualPort}`)
    childPid = child.pid
    child.stdout?.on('data', (chunk) => log(`bubble: ${String(chunk).trim()}`))
    child.stderr?.on('data', (chunk) => log(`bubble! ${String(chunk).trim()}`))
    child.on('error', (error) => {
      log(`bubble process error: ${error?.message ?? error}`)
      child = null
    })
    child.on('exit', (code, signal) => {
      const uptime = Date.now() - startedAt
      log(`bubble exited code=${code} signal=${signal} uptime=${uptime}ms`)
      child = null
      if (disposed) return
      if (userQuit) return
      // A second instance exits immediately because the first one holds the
      // single-instance mutex. The live instance re-hellos when it reconnects,
      // so a recent hello proves it is still serving and this exit is a duplicate.
      if (hello !== null && hello.pid !== 0 && hello.pid !== childPid && Date.now() - hello.at < 6000) {
        log('another bubble instance is serving; not restarting')
        return
      }
      const budget = uptime < 5000 ? 3 : 5
      if (restarts >= budget) {
        log('bubble restart budget exhausted')
        return
      }
      restarts += 1
      spawnTimer = setTimeout(() => {
        spawnTimer = null
        startBubble()
      }, uptime < 5000 ? 4000 : 3000)
      spawnTimer.unref?.()
    })
  }

  const disposers = [
    ctx.on('session/event', onSessionEvent),
    ctx.on('session/disposed', (session) => {
      const sessionId = String(session.id)
      tracks.delete(sessionId)
      if (displaySessionId === sessionId) displaySessionId = null
    }),
  ]

  ctx.effect(() => {
    listen(actualPort, 9)
    log(`plugin ${VERSION} starting (script=${BUBBLE_SCRIPT})`)
    return () => {
      disposed = true
      shuttingDown = true
      for (const dispose of disposers) {
        try {
          dispose()
        } catch {
          /* ignore */
        }
      }
      if (spawnTimer !== null) {
        clearTimeout(spawnTimer)
        spawnTimer = null
      }
      // Let the window notice `shutdown` in its next poll before the socket dies.
      const close = () => {
        if (server !== null) {
          try {
            server.close()
          } catch {
            /* ignore */
          }
          server = null
        }
        if (child !== null) {
          try {
            child.kill()
          } catch {
            /* ignore */
          }
          child = null
        }
        log('plugin disposed')
      }
      const timer = setTimeout(close, 900)
      timer.unref?.()
    }
  })
}
