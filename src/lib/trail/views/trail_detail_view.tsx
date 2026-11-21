import { useEffect } from "react";
import { useParams } from "react-router";
import { useNavigation } from "../../../shared/router/use_navigation";
import TrailMap from "../components/trail_map";
import { useTrailRecorder } from "../hooks/use_trail_recorder";
import { useTrailStore } from "../stores/trail_store";

function TrailDetailView() {
  const { id = "" } = useParams();
  const { goBack } = useNavigation();
  const trail = useTrailStore((state) => state.trails.find((t) => t.id === id));
  const loading = useTrailStore((state) => state.loading);
  const load = useTrailStore((state) => state.load);
  const { recording, error, start, stop } = useTrailRecorder(id);

  // The store may be empty when opening this view directly.
  useEffect(() => {
    if (!trail) load();
  }, [trail, load]);

  if (!trail) {
    return (
      <main className="mx-auto max-w-2xl p-6">
        <p className="text-gray-500">{loading ? "Loading…" : "Trail not found."}</p>
        <button type="button" onClick={goBack} className="mt-4 text-emerald-700 underline">
          Back
        </button>
      </main>
    );
  }

  const pointCount = trail.coordinates.length;
  // The record controls stay visible during a recording, even after the first point arrives.
  const showRecord = pointCount === 0 || recording;

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-4 p-6">
      <button type="button" onClick={goBack} className="self-start text-sm text-emerald-700 underline">
        ← Back
      </button>

      <header>
        <h1 className="text-2xl font-bold">{trail.name}</h1>
        {trail.description && <p className="mt-1 text-gray-600">{trail.description}</p>}
        <p className="mt-2 text-xs text-gray-400">{pointCount} points</p>
      </header>

      {pointCount > 0 && (
        <div className="h-80 overflow-hidden rounded-lg border border-gray-200">
          <TrailMap trail={trail} />
        </div>
      )}

      {showRecord && (
        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={recording ? stop : start}
            className={`rounded-lg px-4 py-2 font-medium text-white ${
              recording ? "bg-red-600 hover:bg-red-700" : "bg-emerald-600 hover:bg-emerald-700"
            }`}
          >
            {recording ? "Stop recording" : "Record"}
          </button>
          {recording && (
            <p className="text-sm text-gray-500">
              Recording: saving your location every 30 seconds. Keep this screen open.
            </p>
          )}
        </div>
      )}

      {error && <p className="text-red-600">{error}</p>}
    </main>
  );
}

export default TrailDetailView;
