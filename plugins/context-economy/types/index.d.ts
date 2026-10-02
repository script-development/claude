// The session values hooks/register.ts keeps in `$.state`.
//
// One value: what a `/clear` left behind, held from `session.end` until the first prompt of the
// conversation after it. In `$.state`, never `$.store`: the store is shared by every session on
// the machine, so a marker there is picked up by whichever session reads it first, not by the one
// that cleared (docs/measured.md finding #41, docs/design.md D32). `$.state` is the session's and
// survives a hot reload of the module, which a module variable does not.
export type ContextEconomyLastClear = {
  // The session the /clear ended: what `claude --resume` takes to get its conversation back.
  sessionId: string
  // Where it ran, absolute; the handoff to surface is this directory's.
  cwd: string
  // When the cleared session began (`$.session.usage().startedAt`, epoch ms). A handoff written
  // before it cannot cover that session.
  startedAt: number
}

declare module 'claude-code' {
  interface PluginState {
    'context-economy': { lastClear: ContextEconomyLastClear | null }
  }
}
