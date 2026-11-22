import { Toaster as Sonner } from "sonner";
import { useColorScheme } from "../../theme/use_color_scheme";

/** Renders toasts shown with `toast.error(...)` from sonner. Mount once at the app root. */
function Toaster() {
  const theme = useColorScheme();
  return (
    <Sonner
      theme={theme}
      position="top-center"
      duration={5000}
      closeButton
      style={{ zIndex: 2000 }}
      offset="calc(12px + env(safe-area-inset-top))"
    />
  );
}

export default Toaster;
