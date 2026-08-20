import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { Menu, X } from "lucide-react";
import { Logo } from "./Logo";

const links = [
  { href: "/#como-funciona", label: "Como funciona" },
  { href: "/#compatibilidade", label: "Compatibilidade" },
  { href: "/#preco", label: "Preço" },
  { href: "/#faq", label: "FAQ" },
];

export function Header() {
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-border/60 bg-background/80 backdrop-blur-xl">
      <nav
        aria-label="Navegação principal"
        className="mx-auto flex h-14 max-w-6xl items-center justify-between px-5"
      >
        <Link to="/" className="flex items-center gap-2" aria-label="Portside — início">
          <Logo className="h-7 w-7" />
          <span className="text-[15px] font-semibold tracking-tight">Portside</span>
        </Link>

        <ul className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <li key={l.href}>
              <a
                href={l.href}
                className="text-[13px] text-muted-foreground transition-colors hover:text-foreground"
              >
                {l.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="flex items-center gap-2">
          <Link
            to="/comprar"
            className="hidden rounded-full bg-gradient-brand px-4 py-1.5 text-[13px] font-medium text-primary-foreground shadow-card transition-opacity hover:opacity-90 md:inline-flex"
          >
            Comprar
          </Link>
          <button
            type="button"
            className="md:hidden"
            aria-expanded={open}
            aria-label={open ? "Fechar menu" : "Abrir menu"}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </nav>

      {open && (
        <div className="border-t border-border/60 px-5 py-4 md:hidden">
          <ul className="flex flex-col gap-4">
            {links.map((l) => (
              <li key={l.href}>
                <a
                  href={l.href}
                  onClick={() => setOpen(false)}
                  className="text-sm text-muted-foreground"
                >
                  {l.label}
                </a>
              </li>
            ))}
            <li>
              <Link
                to="/comprar"
                onClick={() => setOpen(false)}
                className="inline-flex rounded-full bg-gradient-brand px-4 py-2 text-sm font-medium text-primary-foreground"
              >
                Comprar Portside
              </Link>
            </li>
          </ul>
        </div>
      )}
    </header>
  );
}
