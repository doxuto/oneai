/** One notification to one device. Vendor-neutral so tests use a recorder. */
export interface PushMessage {
  token: string;
  title: string;
  body: string;
  /** String-only, as FCM requires. The app routes on `type`. */
  data: Record<string, string>;
  /** Later messages with the same key replace earlier undelivered ones. */
  collapseKey?: string;
}

export interface PushSendResult {
  token: string;
  ok: boolean;
  /** The token is dead (uninstalled, rotated): delete it. */
  unregistered: boolean;
  error?: string;
}

export interface Pusher {
  send(messages: PushMessage[]): Promise<PushSendResult[]>;
}
