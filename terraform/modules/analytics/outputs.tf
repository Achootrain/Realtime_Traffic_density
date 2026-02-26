output "database_name" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.traffic.name
}

output "table_name" {
  description = "Glue catalog table name"
  value       = aws_glue_catalog_table.traffic_stream.name
}

output "workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.primary.name
}
