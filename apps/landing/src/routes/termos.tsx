import { createFileRoute } from "@tanstack/react-router";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";

export const Route = createFileRoute("/termos")({
  head: () => ({
    meta: [
      { title: "Termos de uso — Portside" },
      { name: "description", content: "Termos de uso da licença do aplicativo Portside." },
      { property: "og:title", content: "Termos de uso — Portside" },
      { property: "og:description", content: "Termos de uso da licença do aplicativo Portside." },
    ],
  }),
  component: Termos,
});

function Termos() {
  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-3xl px-5 py-20">
        <h1 className="text-4xl font-semibold">Termos de uso</h1>
        <div className="mt-8 space-y-5 text-[15px] leading-relaxed text-muted-foreground">
          <p>
            A compra do Portside concede uma licença pessoal e intransferível de uso do aplicativo
            em Macs com Apple Silicon.
          </p>
          <p>
            A compatibilidade varia conforme o jogo. O Portside não garante o funcionamento de
            qualquer título específico, especialmente daqueles que dependem de determinados sistemas
            anticheat, drivers ou launchers.
          </p>
          <p>
            O Portside não fornece jogos nem contas. O uso da Steam está sujeito aos termos da Valve
            Corporation.
          </p>
          <p>
            A chave de licença é pessoal. O compartilhamento público da chave pode resultar em sua
            revogação.
          </p>
        </div>
      </main>
      <Footer />
    </div>
  );
}
