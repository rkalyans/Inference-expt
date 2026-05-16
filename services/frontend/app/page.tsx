import Link from "next/link";
import { Cloud, Shirt, Sparkles } from "lucide-react";

export default function Home() {
  return (
    <section className="grid gap-10 py-6 md:grid-cols-[1.2fr_1fr] md:py-12">
      <div>
        <h1 className="text-4xl font-semibold tracking-tight md:text-5xl">
          Pick your outfit the smart way.
        </h1>
        <p className="mt-4 max-w-md text-base text-ink/70">
          Tell Stylist where you’re going. It checks NYC microclimate weather,
          looks through your closet, and recommends a head-to-toe outfit in
          seconds — citing the exact items.
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link href="/login" className="btn-primary">
            <Sparkles className="h-4 w-4" /> Sign in
          </Link>
          <Link href="/chat" className="btn-secondary">
            Try the chat
          </Link>
        </div>
      </div>

      <ul className="grid gap-4 self-start">
        <Feature
          icon={<Cloud className="h-5 w-5" />}
          title="NYC microclimate weather"
          body="Midtown wind, waterfront chill, downtown rain pockets — all baked in."
        />
        <Feature
          icon={<Shirt className="h-5 w-5" />}
          title="Your wardrobe, in the loop"
          body="Photos and tags stay private; the agent only references items you own."
        />
        <Feature
          icon={<Sparkles className="h-5 w-5" />}
          title="Cited recommendations"
          body="Every outfit links back to the items the LLM picked and the weather it used."
        />
      </ul>
    </section>
  );
}

function Feature({
  icon,
  title,
  body,
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
}) {
  return (
    <li className="card flex gap-4">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-accent/10 text-accent">
        {icon}
      </span>
      <div>
        <div className="text-sm font-medium">{title}</div>
        <div className="mt-1 text-sm text-ink/60">{body}</div>
      </div>
    </li>
  );
}
