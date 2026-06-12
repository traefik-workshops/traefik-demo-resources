locals {
  # Encode the user list as JSON for the k6 script. Escape single quotes so it embeds
  # safely inside the single-quoted JSON.parse() argument in scenarios/load.js.
  users_json         = jsonencode([for u in var.users : { username = u.username, password = u.password }])
  users_json_escaped = replace(local.users_json, "'", "\\'")
}
