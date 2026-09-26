# Aufgabe 4: nicht-geheime Infos zur Kontrolle (Passwoerter werden NICHT ausgegeben).
output "db_private_host" {
  description = "Privater Hostname der Managed PostgreSQL (nur im VPC erreichbar)"
  value       = digitalocean_database_cluster.postgres.private_host
}

output "db_port" {
  value = digitalocean_database_cluster.postgres.port
}

output "db_databases" {
  description = "Datenbanken pro Umgebung"
  value       = { for k, db in digitalocean_database_db.app : k => db.name }
}
