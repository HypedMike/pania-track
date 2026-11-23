export const ROUTES = {
  home: "/",
  record: "/record",
  saveRecording: "/record/save",
  importTrail: "/import",
  plan: "/plan",
  planRoutes: "/plan/routes",
  profile: "/profile",
  profileCreate: "/profile/create",
  profileImport: "/profile/import",
  settings: "/settings",
  nostrSettings: "/settings/nostr",
  explore: "/explore",
  exploreTrail: "/explore/:eventId",
  stats: "/stats",
  trailDetail: "/trails/:id",
} as const;

export type AppRoute =
  | (typeof ROUTES)[keyof typeof ROUTES]
  | `/trails/${string}`
  | `/explore/${string}`;

export const trailDetailPath = (id: string): AppRoute => `/trails/${id}`;

export const exploreTrailPath = (eventId: string): AppRoute => `/explore/${eventId}`;
