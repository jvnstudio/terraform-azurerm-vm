locals {
  environment = lower(var.environment)

  private_vm_names = [
    for index in range(var.nb_instances) :
    var.nb_instances == 1 ? var.private_vm_name : format("%s-%02d", var.private_vm_name, index + 1)
  ]

  requested_admin_source_ip = trimspace(var.admin_source_ip != null ? var.admin_source_ip : "")
  detected_admin_source_ip  = var.enable_public_web_vm && local.requested_admin_source_ip == "" ? trimspace(data.http.current_public_ip[0].response_body) : null
  effective_admin_source_ip = !var.enable_public_web_vm ? "*" : (
    local.requested_admin_source_ip == "" ? "${local.detected_admin_source_ip}/32" : (
      local.requested_admin_source_ip == "*" || can(cidrhost(local.requested_admin_source_ip, 0))
      ? local.requested_admin_source_ip
      : "${local.requested_admin_source_ip}/32"
    )
  )

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
