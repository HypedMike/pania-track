import { useEffect } from "react";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { useTrailStore } from "../../trail/stores/trail_store";

function HomeView() {
  const { goTo } = useNavigation();
  const { trails, loading, error, load } = useTrailStore();

  useEffect(() => {
    load();
  }, [load]);

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 p-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trails</h1>
        <button
          type="button"
          onClick={() => goTo(ROUTES.createTrail)}
          className="rounded-lg bg-emerald-600 px-4 py-2 font-medium text-white hover:bg-emerald-700 active:bg-emerald-800"
        >
          Create trail
        </button>
      </header>

      {loading && <p className="text-gray-500">Loading…</p>}
      {error && <p className="text-red-600">Could not load trails: {error}</p>}
      {!loading && !error && trails.length === 0 && (
        <p className="text-gray-500">No trails saved yet.</p>
      )}

      <ul className="flex flex-col gap-3">
        {trails.map((trail) => (
          <li
            key={trail.id}
            onClick={() => goTo(trailDetailPath(trail.id))}
            className="cursor-pointer rounded-lg border border-gray-200 p-4 shadow-sm hover:bg-gray-50"
          >
            <h2 className="font-semibold">{trail.name}</h2>
            {trail.description && (
              <p className="mt-1 text-sm text-gray-600">{trail.description}</p>
            )}
            <p className="mt-2 text-xs text-gray-400">
              {trail.coordinates.length} points
            </p>
          </li>
        ))}
      </ul>
    </main>
  );
}

export default HomeView;
