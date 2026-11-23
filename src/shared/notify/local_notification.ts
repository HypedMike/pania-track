const isAndroid = /android/i.test(navigator.userAgent);

/** Asks once for permission to show notifications where the web API is the only way to do it. */
export async function prepareLocalNotifications(): Promise<void> {
  // On Android the native service posts its own notifications.
  if (isAndroid || typeof Notification === "undefined") return;
  if (Notification.permission === "default") await Notification.requestPermission().catch(() => undefined);
}

/**
 * Shows a system notification from the webview (desktop), and buzzes the device where it can.
 * Does nothing on Android for the notification: the recording service posts it, also when the
 * screen is off and the webview is asleep.
 */
export function notifyLocal(title: string, body: string) {
  try {
    navigator.vibrate?.([300, 150, 300]);
  } catch {
    // Vibration is a nicety.
  }
  if (isAndroid || typeof Notification === "undefined" || Notification.permission !== "granted") return;
  try {
    new Notification(title, { body });
  } catch {
    // Some webviews expose the API but cannot show anything.
  }
}
