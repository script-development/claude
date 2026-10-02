// The values hooks/register.ts keeps across a `/clear`.
//
// What a `/clear` leaves behind is held in `$.store`, under a key naming the process, from
// `session.end` until the first prompt of the conversation after it. Not in `$.state`: that is the
// session's, and a `/clear` starts a new session, so the marker never reached the next prompt
// (docs/measured.md finding #45). Not in `$.store` under one fixed key either: the store is shared
// by every session on the machine, so whichever session read it first took it (finding #41).
export type ContextEconomyLastClear = {
  // The session the /clear ended: what `claude --resume` takes to get its conversation back.
  sessionId: string
  // Where it ran, absolute; the handoff to surface is this directory's.
  cwd: string
  // When the cleared session began (`$.session.usage().startedAt`, epoch ms). A handoff written
  // before it cannot cover that session.
  startedAt: number
  // When the /clear happened, epoch ms: a marker no prompt took is pruned once it is old.
  clearedAt: number
}

declare module 'claude-code' {
  interface PluginState {
    // The process key this load minted, or null. Only its presence matters: it survives a hot reload
    // but not a /clear, so a session.start that finds it set is a reload of a process that already
    // has its key, and one that finds it unset is a fresh process (docs/design.md D32).
    'context-economy': { processKey: string | null }
  }
}
