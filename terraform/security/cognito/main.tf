locals {
  user_pool_name = var.name
  # Cognito hosted-domain prefixes are DNS-label-shaped (hence the underscore
  # swap) and GLOBALLY unique per region.
  domain_prefix = var.domain_prefix != "" ? var.domain_prefix : replace(var.name, "_", "-")
  domain        = var.enable_unique_domain ? "${local.domain_prefix}-${random_id.domain[0].hex}" : local.domain_prefix
}

resource "aws_cognito_user_pool" "pool" {
  name = local.user_pool_name

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = false
    require_numbers                  = false
    require_symbols                  = false
    require_uppercase                = false
    password_history_size            = 0
    temporary_password_validity_days = 30
  }

  # Email verification
  auto_verified_attributes = ["email"]

  # User attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = var.name
  user_pool_id                         = aws_cognito_user_pool.pool.id
  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = var.redirect_uris
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}

# Opt-in randomness for the hosted domain (see enable_unique_domain). Kept
# behind a default-off toggle so existing deployments see no domain replacement.
resource "random_id" "domain" {
  count       = var.enable_unique_domain ? 1 : 0
  byte_length = 3
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.domain
  user_pool_id = aws_cognito_user_pool.pool.id

  lifecycle {
    precondition {
      # AWS rejects these substrings in hosted-domain prefixes — a name like
      # "aws-unified-ingress" needs domain_prefix to override the derived value.
      condition     = length(regexall("aws|amazon|cognito", local.domain)) == 0
      error_message = "Cognito hosted-domain prefixes can't contain \"aws\", \"amazon\", or \"cognito\" (AWS restriction) — set domain_prefix to override the name-derived default."
    }
  }
}

resource "aws_cognito_user" "users" {
  for_each                 = toset(var.users)
  user_pool_id             = aws_cognito_user_pool.pool.id
  username                 = each.key
  desired_delivery_mediums = ["EMAIL"]

  password       = var.user_password
  message_action = "SUPPRESS"

  attributes = {
    email          = "${each.key}@cognito.traefik"
    email_verified = "true"
  }
}

resource "aws_cognito_user_group" "groups" {
  for_each = toset(var.users)

  name         = "${each.value}s"
  description  = "${title(each.value)} group"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_in_group" "user_group_assignments" {
  for_each     = toset(var.users)
  user_pool_id = aws_cognito_user_pool.pool.id
  group_name   = aws_cognito_user_group.groups[each.key].name
  username     = each.key

  depends_on = [aws_cognito_user.users, aws_cognito_user_group.groups]
}
