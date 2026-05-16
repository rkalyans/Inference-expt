"use client";

import { useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { makeApi, type Api, type Item, type Category } from "@/lib/api";
import { useRequireAuth } from "@/lib/use-require-auth";
import { Plus, Shirt, Trash2, UploadCloud } from "lucide-react";

const CATEGORIES: Category[] = ["top", "bottom", "footwear", "outerwear", "accessory"];

export default function WardrobePage() {
  const { fbUser, profile, getToken } = useRequireAuth();
  const api = useMemo(() => makeApi(getToken), [getToken]);

  const [items, setItems] = useState<Item[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (!fbUser) return;
    api
      .listItems()
      .then((d) => setItems(d.items))
      .catch((e) => setErr(String(e)));
  }, [fbUser, api]);

  if (fbUser === undefined || fbUser === null) {
    return <p className="text-sm text-ink/60">Loading…</p>;
  }

  return (
    <section className="space-y-6">
      <header className="flex items-end justify-between">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight">Wardrobe</h1>
          <p className="mt-1 text-sm text-ink/60">
            {items?.length ?? "…"} items · {profile?.email ?? fbUser.email}
          </p>
        </div>
        <button onClick={() => setAdding(true)} className="btn-primary">
          <Plus className="h-4 w-4" /> Add item
        </button>
      </header>

      {err && <p className="card text-sm text-red-600">{err}</p>}

      {items && items.length === 0 && (
        <div className="card grid place-items-center gap-3 py-12 text-center text-sm text-ink/60">
          <Shirt className="h-8 w-8 text-ink/30" />
          Your closet is empty. Add a few items to get personalized outfits.
          <button onClick={() => setAdding(true)} className="btn-primary">
            <Plus className="h-4 w-4" /> Add your first item
          </button>
        </div>
      )}

      {items && items.length > 0 && (
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
          {items.map((it) => (
            <ItemCard
              key={it.id}
              item={it}
              onDelete={async () => {
                await api.deleteItem(it.id);
                setItems((s) => s?.filter((x) => x.id !== it.id) ?? null);
              }}
            />
          ))}
        </div>
      )}

      {adding && (
        <AddItemModal
          api={api}
          onClose={() => setAdding(false)}
          onAdded={(it) => {
            setItems((s) => (s ? [it, ...s] : [it]));
            setAdding(false);
          }}
        />
      )}
    </section>
  );
}

function ItemCard({ item, onDelete }: { item: Item; onDelete: () => void }) {
  return (
    <article className="card group relative space-y-3">
      <div className="relative h-40 w-full overflow-hidden rounded-xl bg-ink/5">
        {item.photo_url ? (
          <Image src={item.photo_url} alt={item.name} fill className="object-cover" />
        ) : (
          <div className="grid h-full w-full place-items-center text-ink/30">
            <Shirt className="h-10 w-10" />
          </div>
        )}
      </div>
      <div>
        <div className="text-sm font-medium">{item.name}</div>
        <div className="text-xs capitalize text-ink/60">{item.category}</div>
      </div>
      <button
        onClick={onDelete}
        className="absolute right-3 top-3 rounded-lg bg-white/90 p-1.5 text-ink/60 opacity-0 shadow-sm transition group-hover:opacity-100 hover:text-red-600"
        aria-label="Delete"
      >
        <Trash2 className="h-4 w-4" />
      </button>
    </article>
  );
}

function AddItemModal({
  api,
  onClose,
  onAdded,
}: {
  api: Api;
  onClose: () => void;
  onAdded: (it: Item) => void;
}) {
  const [name, setName] = useState("");
  const [category, setCategory] = useState<Category>("top");
  const [photo, setPhoto] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setErr(null);
    try {
      let photo_url: string | null = null;
      if (photo) {
        const { upload_url, object_uri } = await api.mintUploadUrl(photo.type || "image/jpeg");
        const put = await fetch(upload_url, {
          method: "PUT",
          headers: { "content-type": photo.type || "image/jpeg" },
          body: photo,
        });
        if (!put.ok) throw new Error(`upload failed: ${put.status}`);
        // object_uri is "gs://bucket/key"; convert to the public-style HTTPS path.
        const m = object_uri.match(/^gs:\/\/([^/]+)\/(.+)$/);
        photo_url = m ? `https://storage.googleapis.com/${m[1]}/${m[2]}` : null;
      }
      const item = await api.createItem({
        name: name.trim(),
        category,
        attributes: {},
        photo_url,
      });
      onAdded(item);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-30 grid place-items-center bg-ink/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="card w-full max-w-md space-y-4"
      >
        <h2 className="text-lg font-semibold">Add an item</h2>

        <label className="block text-sm font-medium">Name</label>
        <input
          className="input"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Navy crewneck"
        />

        <label className="block text-sm font-medium">Category</label>
        <div className="flex flex-wrap gap-2">
          {CATEGORIES.map((c) => (
            <button
              key={c}
              onClick={() => setCategory(c)}
              className={`rounded-xl border px-3 py-1.5 text-sm capitalize ${
                category === c ? "border-ink bg-ink text-white" : "border-ink/15 bg-white"
              }`}
            >
              {c}
            </button>
          ))}
        </div>

        <label className="block text-sm font-medium">Photo (optional)</label>
        <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-dashed border-ink/20 p-3 text-sm text-ink/60 hover:bg-ink/5">
          <UploadCloud className="h-5 w-5" />
          {photo ? photo.name : "Choose a JPEG/PNG"}
          <input
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
          />
        </label>

        {err && <p className="text-sm text-red-600">{err}</p>}

        <div className="flex justify-end gap-3">
          <button onClick={onClose} className="btn-secondary">
            Cancel
          </button>
          <button onClick={submit} disabled={busy || !name.trim()} className="btn-primary">
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}

