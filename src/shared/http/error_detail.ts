const MAX_LENGTH = 200;

/** Pulls a readable message out of an error response body: JSON `message`/`error`, else the trimmed text. */
export function errorDetail(body: string): string {
  let text = body.trim();
  try {
    const json = JSON.parse(text) as { message?: unknown; error?: unknown };
    const field = json.message ?? json.error;
    if (typeof field === "string") text = field.trim();
  } catch {
    // Not JSON: use the raw text.
  }
  // An HTML error page is not worth showing.
  if (!text || /^<(!doctype|html)/i.test(text)) return "";
  return text.length > MAX_LENGTH ? `${text.slice(0, MAX_LENGTH)}…` : text;
}

/** `message`, followed by the server's own explanation when it sent one. */
export function withDetail(message: string, body: string): string {
  const detail = errorDetail(body);
  return detail ? `${message} ${detail}` : message;
}
