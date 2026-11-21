import React from "react";
import ReactDOM from "react-dom/client";
import { RouterProvider } from "react-router";
import { router } from "./shared/router/router";
import { initTheme } from "./shared/theme/theme";
import { initI18n } from "./shared/i18n/i18n";
import "./index.css";

initTheme();
initI18n();

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>,
);
