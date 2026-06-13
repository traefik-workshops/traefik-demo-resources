locals {
  # Encode the lists as JSON for the k6 script. Escape single quotes so they embed safely
  # inside the single-quoted JSON.parse() arguments in scenarios/load.js.
  users_json            = jsonencode([for u in var.users : { username = u.username, password = u.password }])
  users_json_escaped    = replace(local.users_json, "'", "\\'")
  openai_models_json    = replace(jsonencode(var.openai_models), "'", "\\'")
  anthropic_models_json = replace(jsonencode(var.anthropic_models), "'", "\\'")
}
