import { benchmarkNavigator } from "./app";

export function resolveBenchmarkRoute(pathname: string): string {
  return benchmarkNavigator(pathname || "/benchmark");
}
