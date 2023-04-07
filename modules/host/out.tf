# Included for compatibility

output "ipv4_address" {
  value = var.ipv4_address
}

output "private_ipv4_address" {
  value = var.ipv4_address
}

output "name" {
  value = local.name
}

output "id" {
  value = random_string.server.id
}
