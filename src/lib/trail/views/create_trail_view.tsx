import { useState, type FormEvent } from "react";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES } from "../../../shared/router/routes";
import { useTrailStore } from "../stores/trail_store";

function CreateTrailView() {
  const { goTo, goBack } = useNavigation();
  const createTrail = useTrailStore((state) => state.createTrail);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await createTrail({ name, description, coordinates: [] });
      goTo(ROUTES.home, { replace: true });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 p-6">
      <h1 className="text-2xl font-bold">Create trail</h1>

      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1">
          <span className="text-sm font-medium">Name</span>
          <input
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-2 focus:border-emerald-600 focus:outline-none"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-sm font-medium">Description</span>
          <textarea
            rows={4}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-2 focus:border-emerald-600 focus:outline-none"
          />
        </label>

        {error && <p className="text-red-600">Could not save: {error}</p>}

        <div className="flex gap-3">
          <button
            type="submit"
            disabled={saving || name.trim() === ""}
            className="rounded-lg bg-emerald-600 px-4 py-2 font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
          >
            {saving ? "Saving…" : "Save"}
          </button>
          <button
            type="button"
            onClick={goBack}
            className="rounded-lg border border-gray-300 px-4 py-2 font-medium hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </form>
    </main>
  );
}

export default CreateTrailView;
