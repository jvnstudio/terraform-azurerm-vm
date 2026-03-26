locals {
  environment = lower(var.environment)

  effective_tags = merge(
    var.tags,
    {
      environment = local.environment
    }
  )

  ansible_inventory_output_path = (
    try(length(trimspace(var.ansible_inventory_file)) > 0, false)
    ? var.ansible_inventory_file
    : "${path.module}/ansible/inventories/${local.environment}/hosts.ini"
  )
}
