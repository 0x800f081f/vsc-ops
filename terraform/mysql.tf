# Aufgabe 6: DigitalOcean Managed MySQL fuer den module_service.
# Nur der module_service bekommt Zugangsdaten (Secret "module-service-db").
# Der user_mgmt_service erhaelt sie nie und spricht den module_service
# ausschliesslich ueber dessen REST-API an.

resource "digitalocean_database_cluster" "mysql" {
  name       = var.mysql_cluster_name
  engine     = "mysql"
  version    = var.mysql_version
  size       = var.mysql_size
  region     = var.region
  node_count = 1

  # Gleiches VPC wie der Cluster -> Verbindung ueber das private Netz
  private_network_uuid = digitalocean_kubernetes_cluster.teko_doks.vpc_uuid
}

# Getrennte Datenbank + Benutzer pro Umgebung (wie bei PostgreSQL)
resource "digitalocean_database_db" "module_service" {
  for_each   = local.environments
  cluster_id = digitalocean_database_cluster.mysql.id
  name       = "module_service_${each.key}"
}

resource "digitalocean_database_user" "module_service" {
  for_each   = local.environments
  cluster_id = digitalocean_database_cluster.mysql.id
  name       = "module_service_${each.key}"

  # Wie bei PostgreSQL: leerer "settings {}"-Block der DO-API ignorieren
  lifecycle {
    ignore_changes = [settings]
  }
}
