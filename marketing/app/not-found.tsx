import Link from "next/link";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";

export default function NotFound() {
  return (
    <>
      <Nav variant="dark" />
      <main className="bg-white">
        <section className="container-x flex min-h-[60vh] flex-col items-center justify-center py-24 text-center">
          <div className="text-7xl font-extrabold tracking-tight text-navy-900">
            404
          </div>
          <h1 className="mt-4 text-2xl font-bold text-navy-900 sm:text-3xl">
            Страница не найдена
          </h1>
          <p className="mt-3 max-w-md text-base text-slate-600">
            Возможно, ссылка устарела или вы открыли её по ошибке. Вернитесь
            на главную или загляните в категории.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <Link href="/" className="btn-primary">
              На главную
            </Link>
            <Link
              href="/#verticals"
              className="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200 px-6 py-3 text-sm font-semibold text-navy-900 transition hover:border-navy-900 hover:bg-slate-50"
            >
              Категории
            </Link>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
