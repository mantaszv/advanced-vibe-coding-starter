import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <h1 className="text-3xl font-semibold tracking-tight">mini-CRM</h1>
      <p className="text-muted-foreground max-w-md text-center">
        Lengvas CRM lietuviškoms paslaugų SMĮ. Projektas dar kuriamas.
      </p>
      <Button>Pradėti</Button>
    </main>
  );
}
