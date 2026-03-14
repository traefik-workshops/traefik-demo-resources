import { useState, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  useLocalRuntime,
  AssistantRuntimeProvider,
  type ChatModelAdapter,
  type ChatModelRunOptions,
} from '@assistant-ui/react'
import { Thread } from '@assistant-ui/react-ui'
import ModelPicker from './ModelPicker'
import McpServerToggles from './McpServerToggles'
import { config } from '../../lib/config'
import type { McpServer } from '../../types'

// ── Chat model adapter — calls ai-gateway /chat/completions ─────────────────
function makeAdapter(modelId: string, enabledMcp: Set<string>): ChatModelAdapter {
  return {
    async *run({ messages, abortSignal }: ChatModelRunOptions) {
      const activeMcp: McpServer[] = config.mcpServers.filter((s) => enabledMcp.has(s.id))
      const tools = activeMcp.flatMap((srv) =>
        srv.tools.map((name) => ({
          type: 'function' as const,
          function: {
            name: `${srv.id}__${name}`,
            description: `MCP tool ${name} from ${srv.label}`,
            parameters: { type: 'object', properties: {} },
          },
        })),
      )

      const res = await fetch(`${config.aiGatewayUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(config.aiGatewayToken ? { Authorization: `Bearer ${config.aiGatewayToken}` } : {}),
        },
        body: JSON.stringify({
          model: modelId,
          messages: messages.map((m) => ({ role: m.role, content: m.content })),
          stream: true,
          ...(tools.length > 0 ? { tools } : {}),
        }),
        signal: abortSignal,
      })

      if (!res.ok) throw new Error(`AI gateway error: ${res.status}`)

      const reader = res.body!.getReader()
      const decoder = new TextDecoder()
      let text = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        const chunk = decoder.decode(value, { stream: true })
        for (const line of chunk.split('\n')) {
          if (!line.startsWith('data:')) continue
          const data = line.slice(5).trim()
          if (data === '[DONE]') break
          try {
            const delta = JSON.parse(data).choices?.[0]?.delta?.content ?? ''
            text += delta
            yield { content: [{ type: 'text' as const, text }] }
          } catch { /* skip malformed SSE lines */ }
        }
      }
    },
  }
}

// ── Inner panel — needs to be inside AssistantRuntimeProvider ───────────────
function ChatPanelInner() {
  const [modelId, setModelId] = useState('')
  const [enabledMcp, setEnabledMcp] = useState<Set<string>>(new Set())
  const [configOpen, setConfigOpen] = useState(true)

  const adapter = useCallback(
    () => makeAdapter(modelId, enabledMcp),
    [modelId, enabledMcp],
  )

  const runtime = useLocalRuntime(adapter())

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <div className="flex flex-col h-full">
        {/* Config — model picker + MCP toggles */}
        <div className="border-b" style={{ borderColor: 'var(--color-border)' }}>
          <button
            onClick={() => setConfigOpen((v) => !v)}
            className="w-full flex items-center justify-between px-4 py-2.5 text-xs uppercase tracking-wider hover:opacity-80 transition-opacity"
            style={{ color: 'var(--color-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer' }}
          >
            <span>Configuration</span>
            <span>{configOpen ? '▲' : '▼'}</span>
          </button>

          <AnimatePresence initial={false}>
            {configOpen && (
              <motion.div
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: 'auto', opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="overflow-hidden"
              >
                <div className="px-4 pb-4 flex flex-col gap-4">
                  <ModelPicker value={modelId} onChange={setModelId} />
                  <McpServerToggles enabled={enabledMcp} onChange={setEnabledMcp} />
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Thread */}
        <div className="flex-1 overflow-hidden">
          <Thread />
        </div>
      </div>
    </AssistantRuntimeProvider>
  )
}

// ── Floating button + slide-in panel ────────────────────────────────────────
export default function AiChatPanel() {
  const [open, setOpen] = useState(false)

  if (!config.aiGatewayEnabled) return null

  return (
    <>
      <motion.button
        onClick={() => setOpen((v) => !v)}
        className="fixed bottom-6 right-6 z-40 w-12 h-12 rounded-full flex items-center justify-center shadow-lg text-lg border-0 cursor-pointer"
        style={{
          background: open ? 'var(--color-bg-tertiary)' : 'var(--color-accent-amber)',
          color: open ? 'var(--color-text-secondary)' : '#0f172a',
        }}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        title={open ? 'Close AI chat' : 'Open AI chat'}
      >
        {open ? '✕' : '✦'}
      </motion.button>

      <AnimatePresence>
        {open && (
          <motion.div
            className="fixed bottom-24 right-6 z-40 w-96 rounded-xl border shadow-2xl flex flex-col overflow-hidden"
            style={{
              height: '560px',
              background: 'var(--color-bg-secondary)',
              borderColor: 'var(--color-border)',
            }}
            initial={{ opacity: 0, y: 20, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.97 }}
            transition={{ duration: 0.2 }}
          >
            <div
              className="flex items-center gap-2 px-4 py-3 border-b text-xs font-medium uppercase tracking-widest"
              style={{ borderColor: 'var(--color-border)', color: 'var(--color-accent-amber)' }}
            >
              <span>✦</span>
              <span>AI Assistant</span>
            </div>

            <div className="flex-1 overflow-hidden">
              <ChatPanelInner />
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  )
}
