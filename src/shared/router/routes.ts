export const ROUTES = {
  home: "/",
  record: "/record",
  saveRecording: "/record/save",
  importTrail: "/import",
  settings: "/settings",
  trailDetail: "/trails/:id",
} as const;

export type AppRoute =
  | (typeof ROUTES)[keyof typeof ROUTES]
  | `/trails/${string}`;

export const trailDetailPath = (id: string): AppRoute => `/trails/${id}`;
