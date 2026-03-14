/** Runtime config injected by Helm into index.html as window globals. */
export const config = {
  get aiGatewayEnabled(): boolean {
    return window.AI_GATEWAY_ENABLED ?? false
  },
  get aiGatewayUrl(): string {
    return window.AI_GATEWAY_URL ?? ''
  },
  get aiGatewayToken(): string | undefined {
    return window.AI_GATEWAY_TOKEN
  },
  get mcpServers() {
    return window.MCP_SERVERS ?? []
  },
}
