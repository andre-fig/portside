import { Link } from "@tanstack/react-router";
import { Logo } from "./Logo";

export function Footer() {
  return (
    <footer className="border-t border-border/60 bg-secondary/40">
      <div className="mx-auto max-w-6xl px-5 py-12">
        <div className="flex flex-col gap-8 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-2">
            <Logo className="h-6 w-6" />
            <span className="text-sm font-semibold">Portside</span>
          </div>
          <nav aria-label="Rodapé">
            <ul className="flex flex-wrap gap-6 text-[13px] text-muted-foreground">
              <li>
                <Link to="/termos" className="hover:text-foreground">
                  Termos
                </Link>
              </li>
              <li>
                <Link to="/privacidade" className="hover:text-foreground">
                  Privacidade
                </Link>
              </li>
              <li>
                <Link to="/suporte" className="hover:text-foreground">
                  Suporte
                </Link>
              </li>
            </ul>
          </nav>
        </div>
        <p className="mt-8 max-w-3xl text-[12px] leading-relaxed text-muted-foreground">
          Portside é um produto independente e não é afiliado, patrocinado ou endossado pela Valve
          Corporation ou pela Apple Inc. Steam é uma marca da Valve Corporation.
        </p>
        <p className="mt-3 text-[12px] text-muted-foreground">
          © {new Date().getFullYear()} Portside. Todos os direitos reservados.
        </p>
      </div>
    </footer>
  );
}
