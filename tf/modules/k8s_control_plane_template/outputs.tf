output "template_id" {
  value = aws_launch_template.experiments_k8s_control_plane_template.id
  description = "ID of the template"
}

output "template_latest_version" {
  value = aws_launch_template.experiments_k8s_control_plane_template.latest_version
  description = "Version of the template"
}

output "security_group_id" {
  value = aws_security_group.this.id
  description = "ID of the security group"
}