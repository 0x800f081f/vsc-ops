# Nicht-geheime Infos zur Kontrolle (Passwoerter werden NICHT ausgegeben).
output "db_private_host" {
  description = "Privater Hostname der Managed PostgreSQL (nur im VPC aufloesbar)"
  value       = digitalocean_database_cluster.postgres.private_host
}

output "db_port" {
  value = digitalocean_database_cluster.postgres.port
}

output "db_databases" {
  description = "PostgreSQL-Datenbanken pro Umgebung"
  value       = { for k, db in digitalocean_database_db.app : k => db.name }
}

output "mysql_private_host" {
  description = "Privater Hostname der Managed MySQL (nur im VPC aufloesbar)"
  value       = digitalocean_database_cluster.mysql.private_host
}

output "mysql_databases" {
  description = "MySQL-Datenbanken pro Umgebung"
  value       = { for k, db in digitalocean_database_db.module_service : k => db.name }
}
