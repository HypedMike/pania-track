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
  stats: "/stats",
  trailDetail: "/trails/:id",
} as const;

export type AppRoute =
  | (typeof ROUTES)[keyof typeof ROUTES]
  | `/trails/${string}`;

export const trailDetailPath = (id: string): AppRoute => `/trails/${id}`;
