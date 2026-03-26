locals {
  environment = lower(var.environment)

  private_vm_names = [
    for index in range(var.nb_instances) :
    var.nb_instances == 1 ? var.private_vm_name : format("%s-%02d", var.private_vm_name, index + 1)
  ]

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
