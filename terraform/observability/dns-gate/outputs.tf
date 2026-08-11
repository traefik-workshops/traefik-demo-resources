output "id" {
  value       = null_resource.gate.id
  description = "Depend on this from every spoke that ships OTLP to the gated hostname. Use it in the spoke module's depends_on — an implicit reference is not enough, because the spoke does not consume any value from the gate and terraform would otherwise be free to build them concurrently."
}
