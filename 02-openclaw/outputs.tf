output "instance_id" {
  description = "Instance ID for SSM Session Manager connection"
  value       = aws_instance.openclaw.id
}
