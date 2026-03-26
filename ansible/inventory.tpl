%{ if enable_web_vm ~}
[webservers]
${web_vm_public_ip} ansible_user=${admin_username} ansible_ssh_private_key_file=${replace(ssh_key_path, ".pub", "")} private_ip=${web_vm_private_ip}
%{ endif ~}

%{ if length(private_vm_ips) > 0 ~}
[private]
%{ for ip in private_vm_ips ~}
${ip} ansible_user=${admin_username} ansible_ssh_private_key_file=${replace(ssh_key_path, ".pub", "")}
%{ endfor ~}
%{ endif ~}

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{ if enable_web_vm ~}
web_vm_private_ip=${web_vm_private_ip}
%{ endif ~}
%{ if enable_bastion ~}

[private:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="az network bastion tunnel --name ${bastion_name} --resource-group ${resource_group_name} --target-resource-id %%h --resource-port 22 --port %%p"'
%{ endif ~}
