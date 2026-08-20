import { createFileRoute } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import { Check, Copy, Download, FileKey, Mail } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";
import { getOrderStatus } from "@/lib/order.functions";

export const Route = createFileRoute("/sucesso")({
  validateSearch: z.object({ session_id: z.string().optional() }),
  head: () => ({
    meta: [
      { title: "Pagamento confirmado — Portside" },
      {
        name: "description",
        content: "Baixe o Portside e acesse sua chave de licença após a confirmação do pagamento.",
      },
      { name: "robots", content: "noindex" },
      { property: "og:title", content: "Pagamento confirmado — Portside" },
      { property: "og:description", content: "Sua licença do Portside." },
    ],
  }),
  component: Sucesso,
});

function Sucesso() {
  const { session_id } = Route.useSearch();
  const fetchOrder = useServerFn(getOrderStatus);
  const [copied, setCopied] = useState(false);

  const { data, isPending } = useQuery({
    queryKey: ["order", session_id],
    enabled: Boolean(session_id),
    refetchInterval: (q) => (q.state.data?.status === "confirmed" ? false : 4000),
    queryFn: () => fetchOrder({ data: { sessionId: session_id! } }),
  });

  function copyKey(license: string) {
    void navigator.clipboard.writeText(license);
    setCopied(true);
    toast.success("Chave copiada");
    setTimeout(() => setCopied(false), 2000);
  }

  function downloadKey(license: string) {
    const content = `Portside — chave de licença\n\n${license}\n\nAbra o Portside e cole a chave na tela de ativação.\nNão compartilhe esta chave publicamente.\n`;
    const url = URL.createObjectURL(new Blob([content], { type: "text/plain" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "portside-license.txt";
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-2xl px-5 py-20">
        {!session_id ? (
          <Panel
            title="Nada para mostrar aqui"
            text="Esta página exibe sua licença apenas após uma compra confirmada."
          />
        ) : isPending || data?.status === "pending" ? (
          <Panel
            title="Confirmando seu pagamento"
            text={
              data?.status === "pending"
                ? data.message
                : "Aguarde alguns instantes enquanto validamos o pagamento com segurança."
            }
          />
        ) : data?.status === "confirmed" ? (
          <div className="reveal">
            <span className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-gradient-brand text-primary-foreground">
              <Check className="h-6 w-6" aria-hidden />
            </span>
            <h1 className="mt-6 text-4xl font-semibold">Pagamento confirmado</h1>
            <p className="mt-3 text-[15px] text-muted-foreground">
              Enviamos a licença e o link de download para {data.email}.
            </p>

            <a
              href={data.downloadUrl}
              className="mt-8 inline-flex items-center gap-2 rounded-full bg-gradient-brand px-6 py-3 text-[15px] font-medium text-primary-foreground"
            >
              <Download className="h-4 w-4" aria-hidden />
              Baixar Portside
            </a>

            <div className="mt-10 rounded-3xl border border-border/70 bg-card p-7 shadow-card">
              <h2 className="text-sm font-medium text-muted-foreground">Chave de licença</h2>
              <p className="mt-2 font-mono text-lg break-all">{data.license}</p>
              <div className="mt-5 flex flex-wrap gap-3">
                <button
                  onClick={() => copyKey(data.license)}
                  className="inline-flex items-center gap-2 rounded-full border border-border px-4 py-2 text-sm hover:bg-secondary"
                >
                  <Copy className="h-4 w-4" aria-hidden />
                  {copied ? "Copiada" : "Copiar chave"}
                </button>
                <button
                  onClick={() => downloadKey(data.license)}
                  className="inline-flex items-center gap-2 rounded-full border border-border px-4 py-2 text-sm hover:bg-secondary"
                >
                  <FileKey className="h-4 w-4" aria-hidden />
                  Baixar chave
                </button>
                <button
                  onClick={() => toast.success("Reenvio solicitado. Verifique seu e-mail.")}
                  className="inline-flex items-center gap-2 rounded-full border border-border px-4 py-2 text-sm hover:bg-secondary"
                >
                  <Mail className="h-4 w-4" aria-hidden />
                  Reenviar por e-mail
                </button>
              </div>
            </div>

            <ol className="mt-8 space-y-2 text-[15px] text-muted-foreground">
              <li>1. Baixe o Portside e arraste-o para a pasta Aplicativos.</li>
              <li>2. Abra o Portside e cole a chave de licença.</li>
              <li>3. Entre na Steam, instale um jogo e comece a jogar.</li>
            </ol>
          </div>
        ) : (
          <Panel
            title="Não foi possível verificar o pedido"
            text="Tente recarregar a página em instantes ou fale com o suporte."
          />
        )}
      </main>
      <Footer />
    </div>
  );
}

function Panel({ title, text }: { title: string; text: string }) {
  return (
    <div className="rounded-3xl border border-border/70 bg-card p-9 shadow-card">
      <h1 className="text-2xl font-semibold">{title}</h1>
      <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">{text}</p>
    </div>
  );
}
