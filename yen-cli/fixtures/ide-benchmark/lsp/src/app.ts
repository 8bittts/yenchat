export function benchmarkNavigator(input: string): string {
  return input.trim().toUpperCase();
}

export function renderBenchmarkSummary(): string {
  return benchmarkNavigator("fixture search and lsp benchmark");
}
