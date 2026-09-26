# Aufgabe 4: DigitalOcean Managed PostgreSQL - ersetzt den bisherigen DB-Pod im Cluster.
# Eine gemeinsame Instanz, darin je eine Datenbank + ein Benutzer pro Umgebung.

locals {
  environments = toset(["staging", "prod"])
}

resource "digitalocean_database_cluster" "postgres" {
  name       = var.db_cluster_name
  engine     = "pg"
  version    = var.db_version
  size       = var.db_size
  region     = var.region
  node_count = 1

  # Im selben VPC wie der Kubernetes-Cluster -> das Backend verbindet sich
  # ueber das private Netz, nicht ueber das Internet.
  private_network_uuid = digitalocean_kubernetes_cluster.teko_doks.vpc_uuid
}

# Getrennte Datenbanken pro Umgebung (user_mgmt_staging / user_mgmt_prod)
resource "digitalocean_database_db" "app" {
  for_each   = local.environments
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "user_mgmt_${each.key}"
}

# Getrennte Benutzer pro Umgebung. Das Passwort erzeugt DigitalOcean.
resource "digitalocean_database_user" "app" {
  for_each   = local.environments
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "user_mgmt_${each.key}"

  # Die DO-API liefert beim Auslesen einen leeren "settings {}"-Block (gilt nur
  # fuer Kafka/OpenSearch-ACLs, bei PostgreSQL immer leer). Ohne diese Zeile
  # wuerde jeder "terraform plan" eine sinnlose Aenderung anzeigen.
  lifecycle {
    ignore_changes = [settings]
  }
}

# Ab PostgreSQL 15 darf ein neuer Benutzer im Schema "public" keine Tabellen
# anlegen ("permission denied for schema public"). Hibernate (ddl-auto=update)
# muss das aber. Deshalb: CREATE + USAGE auf "public" - jeweils NUR in der
# eigenen Datenbank der Umgebung.
resource "postgresql_grant" "schema_public" {
  for_each    = local.environments
  database    = digitalocean_database_db.app[each.key].name
  role        = digitalocean_database_user.app[each.key].name
  schema      = "public"
  object_type = "schema"
  privileges  = ["CREATE", "USAGE"]
}
