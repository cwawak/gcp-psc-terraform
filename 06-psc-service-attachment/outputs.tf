# --- Outputs ---
output "service_attachment_uri" {
  description = "The PSC Service Attachment URI to configure in Confluent HTTP Sink connector"
  value       = google_compute_service_attachment.confluent_https_service.self_link
}

output "service_attachment_id" {
  description = "The PSC Service Attachment ID"
  value       = google_compute_service_attachment.confluent_https_service.id
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_region_backend_service.https_backend.name
}

output "forwarding_rule_name" {
  description = "Name of the forwarding rule"
  value       = google_compute_forwarding_rule.https_forwarding_rule.name
}

output "health_check_name" {
  description = "Name of the health check"
  value       = google_compute_health_check.https_health_check.name
}

output "psc_subnet_name" {
  description = "Name of the dedicated PSC subnet"
  value       = google_compute_subnetwork.psc_subnet.name
}

output "firewall_rule_name" {
  description = "Name of the health check firewall rule"
  value       = google_compute_firewall.allow_health_checks.name
}

output "vm_internal_ip" {
  description = "Internal IP of the target VM"
  value       = data.google_compute_instance.existing_vm.network_interface[0].network_ip
}

output "psc_subnet_cidr" {
  description = "CIDR range of the PSC subnet"
  value       = google_compute_subnetwork.psc_subnet.ip_cidr_range
}

output "instance_group_name" {
  description = "Name of the instance group"
  value       = google_compute_instance_group.https_vm_group.name
}